// Bucket General Allocator

const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const sync = root.sync;
const buddy = root.mem.buddy;
const page = root.mem.page;
const hal_page = root.hal.page;
const is_debug = @import("builtin").mode == .Debug;

const bucket_min_size = @sizeOf(usize);
const bucket_max_size = hal_page.page_size * 2;
const bucket_sizes_num = std.math.log2(bucket_max_size / bucket_min_size) + 1;
const bucket_sizes = blk: {
    var sizes: [bucket_sizes_num]usize = undefined;
    for (0..bucket_sizes_num) |i| {
        sizes[i] = (@as(usize, 1) << i) * bucket_min_size;
    }
    break :blk sizes;
};
comptime {
    assert(bucket_sizes[0] == bucket_min_size);
    assert(bucket_sizes[bucket_sizes_num - 1] == bucket_max_size);
}

var bucket_list: [bucket_sizes_num]?hal_page.PageIndex = .{null} ** bucket_sizes_num;
var bucket_lock: sync.SpinLockIrq = .unlocked;

const BucketPrivate = packed struct(u64) {
    free_count: u15,
    head: u15,
    _reserved: u34,
};
const BlockMeta = packed struct(u16) {
    has_next: bool,
    next: u15,
};
inline fn getBlockMeta(page_index: hal_page.PageIndex, bucket_size: usize, block_index: u15) *BlockMeta {
    const page_base = hal_page.direct_map_base + hal_page.index2addr(page_index);
    return @ptrFromInt(page_base + bucket_size * block_index);
}

/// NOTE: Must acquire bucket_lock before call
fn allocBucket(bucket_index: u8) !void {
    assert(bucket_list[bucket_index] == null);
    const bucket_size = bucket_sizes[bucket_index];
    var alloc_order: u8 = @intCast(std.math.log2(@max(bucket_size * 4, hal_page.page_size) / hal_page.page_size));
    while (true) : (alloc_order -= 1) {
        if (buddy.alloc(alloc_order, .bucket)) |page_index| {
            // Add to bucket_list
            const meta = page.getMeta(page_index);
            meta.list.setNext(null);
            meta.list.setPrev(null);
            bucket_list[bucket_index] = page_index;
            // Divide memory blocks
            const private: *BucketPrivate = @ptrCast(&meta.private);
            const blocks_num = buddy.orderSize(alloc_order) * hal_page.page_size / bucket_size;
            private.free_count = @intCast(blocks_num);
            private.head = 0;
            // log.debug(@src(), "page {}: divide to {} blocks", .{ page_index, blocks_num });
            for (0..blocks_num) |i| {
                const block_meta: *BlockMeta = getBlockMeta(page_index, bucket_size, @intCast(i));
                if (i + 1 != blocks_num) {
                    block_meta.has_next = true;
                    block_meta.next = @intCast(i + 1);
                } else {
                    block_meta.has_next = false;
                }
            }

            return;
        }
        if (alloc_order == 0) break;
    }
    return error.OutOfMemory;
}

fn alloc(bucket_index: u8) ?[*]u8 {
    const flag = bucket_lock.lock();
    defer bucket_lock.unlock(flag);

    if (bucket_list[bucket_index] == null) {
        allocBucket(bucket_index) catch return null;
    }

    const page_index = bucket_list[bucket_index].?;
    const meta = page.getMeta(page_index);
    const private: *BucketPrivate = @ptrCast(&meta.private);
    assert(private.free_count != 0);
    const bucket_size = bucket_sizes[bucket_index];
    const block_meta = getBlockMeta(page_index, bucket_size, private.head);
    if (block_meta.has_next) {
        private.free_count -= 1;
        private.head = block_meta.next;
    } else {
        assert(private.free_count == 1);
        private.free_count = 0;
        bucket_list[bucket_index] = meta.list.next();
        if (meta.list.next()) |next_index| {
            const next_meta = page.getMeta(next_index);
            next_meta.list.setPrev(null);
        }
    }

    return @ptrCast(block_meta);
}

fn free(bucket_index: u8, ptr: [*]u8) void {
    const flag = bucket_lock.lock();
    defer bucket_lock.unlock(flag);

    const bucket_size = bucket_sizes[bucket_index];
    const paddr = @intFromPtr(ptr) - hal_page.direct_map_base;
    assert(paddr % bucket_size == 0);
    const meta_tail = page.getMeta(@truncate(paddr >> hal_page.page_shift));
    assert(meta_tail.type == .bucket or meta_tail.type == .tail);
    const page_index = meta_tail.compound.head;
    const meta = page.getMeta(page_index);
    assert(meta.type == .bucket);
    const block_index: u15 = @intCast((paddr - hal_page.index2addr(page_index)) / bucket_size);
    assert((paddr - hal_page.index2addr(page_index)) % bucket_size == 0);
    const block_meta = getBlockMeta(page_index, bucket_size, block_index);

    const private: *BucketPrivate = @ptrCast(&meta.private);
    if (private.free_count == 0) {
        block_meta.has_next = false;
        private.free_count = 1;
        private.head = block_index;
        // Add to bucket_list
        if (bucket_list[bucket_index]) |next_page_index| {
            bucket_list[bucket_index] = page_index;
            meta.list.setNext(next_page_index);
            meta.list.setPrev(null);

            const next_meta = page.getMeta(next_page_index);
            assert(next_meta.type == .bucket);
            next_meta.list.setPrev(page_index);
        } else {
            bucket_list[bucket_index] = page_index;
            meta.list.setNext(null);
            meta.list.setPrev(null);
        }
    } else {
        block_meta.has_next = true;
        block_meta.next = private.head;
        private.free_count += 1;
        private.head = block_index;
        // If all released, return page to buddy.
        const blocks_num = buddy.orderSize(meta.compound.order) * hal_page.page_size / bucket_size;
        if (private.free_count == blocks_num) {
            if (meta.list.next()) |next_index| {
                const next_meta = page.getMeta(next_index);
                next_meta.list.setPrev(meta.list.prev());
            }
            if (meta.list.prev()) |prev_index| {
                const prev_meta = page.getMeta(prev_index);
                prev_meta.list.setNext(meta.list.next());
            } else {
                // First node, so we update free_list
                bucket_list[bucket_index] = meta.list.next();
            }
            meta.list.setNext(null);
            meta.list.setPrev(null);

            buddy.unref(page_index);
        }
    }
}

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};
const vtable: std.mem.Allocator.VTable = .{
    .alloc = allocFunc,
    .free = freeFunc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
};

inline fn bucketIndex(len: usize) ?u8 {
    for (0..bucket_sizes_num) |i| {
        if (len <= bucket_sizes[i]) {
            return @intCast(i);
        }
    }
    return null;
}

inline fn order(len: usize) u8 {
    assert(len >= hal_page.page_size);
    return @intCast(std.math.log2_int_ceil(usize, len >> hal_page.page_shift));
}

const DebugMeta = packed struct(usize) {
    magic: u16 = 0xABCD,
    len: @Int(.unsigned, @bitSizeOf(usize) - 16),
};

fn allocFunc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    if (is_debug) {
        assert(hal_page.page_size >= alignment.toByteUnits());
        const ptr: [*]u8 = if (len <= hal_page.page_size) blk: {
            const bucket_index = bucketIndex(len).?;
            assert(bucket_sizes[bucket_index] >= alignment.toByteUnits());
            const meta: *DebugMeta = @ptrCast(@alignCast(alloc(bucket_index + 1) orelse return null));
            meta.* = .{ .len = @intCast(len) };
            break :blk @ptrFromInt(@intFromPtr(meta) + bucket_sizes[bucket_index]);
        } else if (buddy.alloc(order(len) + 1, .bucket)) |page_index| blk: {
            const meta_vaddr = hal_page.direct_map_base + hal_page.index2addr(page_index);
            const meta: *DebugMeta = @ptrFromInt(meta_vaddr);
            meta.* = .{ .len = @intCast(len) };
            break :blk @ptrFromInt(meta_vaddr + buddy.orderSize(order(len)) * hal_page.page_size);
        } else return null;
        @memset(ptr[0..len], 0xAA);
        return ptr;
    } else {
        if (bucketIndex(len)) |bucket_index| {
            return alloc(bucket_index);
        } else if (buddy.alloc(order(len), .bucket)) |page_index| {
            return @ptrFromInt(hal_page.direct_map_base + hal_page.index2addr(page_index));
        } else {
            return null;
        }
    }
}

fn freeFunc(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, _: usize) void {
    if (is_debug) {
        assert(hal_page.page_size >= alignment.toByteUnits());
        @memset(memory, 0xFE);
        if (memory.len <= hal_page.page_size) {
            const bucket_index = bucketIndex(memory.len).?;
            assert(bucket_sizes[bucket_index] >= alignment.toByteUnits());
            const meta: *DebugMeta = @ptrFromInt(@intFromPtr(memory.ptr) - bucket_sizes[bucket_index]);
            if (meta.magic == 0x1234) @panic("Double free");
            if (meta.magic != 0xABCD or meta.len != memory.len) @panic("Bad free");
            meta.magic = 0x1234;
            free(bucket_index + 1, @ptrCast(meta));
        } else {
            const meta: *DebugMeta = @ptrFromInt(@intFromPtr(memory.ptr) - buddy.orderSize(order(memory.len)) * hal_page.page_size);
            if (meta.magic == 0x1234) @panic("Double free");
            if (meta.magic != 0xABCD or meta.len != memory.len) @panic("Bad free");
            meta.magic = 0x1234;
            buddy.unref(@truncate((@intFromPtr(meta) - hal_page.direct_map_base) >> hal_page.page_shift));
        }
    } else {
        if (bucketIndex(memory.len)) |bucket_index| {
            return free(bucket_index, memory.ptr);
        } else {
            buddy.unref(@truncate((@intFromPtr(memory.ptr) - hal_page.direct_map_base) >> hal_page.page_shift));
        }
    }
}
