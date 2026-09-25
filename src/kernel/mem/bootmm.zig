// Boot Stage Memory Manager
// NOTE: Single-threaded

const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const hal_page = root.hal.page;
const mem = root.mem;
const log = root.debug.log;

var memory: []Region = undefined;
var memory_count: usize = 0;
var reserved: []Region = undefined;
var reserved_count: usize = 0;
var is_expanding: bool = false;

const Region = struct {
    base: hal_page.PhysAddr,
    len: usize,
    type: RegionType,
};
pub const RegionType = enum {
    /// The region can be used now
    usable,
    /// The region is unusable now, but it will be usable later
    no_alloc,
    /// Unusable permanently
    occupied,
    /// Unusable permanently, and should never be mapped
    no_map,
    /// Sentinel, DO NOT USE
    sentinel,
};
const sentinel_region: Region = .{
    .base = std.mem.alignBackward(
        hal_page.PhysAddr,
        std.math.maxInt(hal_page.PhysAddr),
        hal_page.page_size,
    ),
    .len = 0,
    .type = .sentinel,
};

const init_regions_count = hal_page.page_size / @sizeOf(Region);
pub const requested_size = hal_page.page_size;
pub const requested_align = hal_page.page_size;
pub fn init(buffer: *align(requested_align) [2][requested_size]u8) void {
    memory.ptr = @ptrFromInt(@intFromPtr(&buffer[0]) - hal_page.kernel_base + hal_page.direct_map_base);
    memory.len = init_regions_count;
    reserved.ptr = @ptrFromInt(@intFromPtr(&buffer[1]) - hal_page.kernel_base + hal_page.direct_map_base);
    reserved.len = init_regions_count;
}

/// Deinitialize bootmm, and transfer all pages to buddy
pub fn switchToBuddy() void {
    const buddy = mem.buddy;

    var max_paddr: hal_page.PhysAddr = 0;
    for (memory[0 .. memory_count + 1]) |region| {
        if (region.type != .usable and region.type != .no_alloc) continue;
        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);
        max_paddr = @max(max_paddr, region.base + region.len);
    }
    buddy.init(@intCast(max_paddr / hal_page.page_size));

    // Use rawFree to prevent zig from filling the released memory with 0xAA
    if (memory.len != init_regions_count) {
        allocator.rawFree(@ptrCast(memory), .fromByteUnits(requested_align), 0);
    }
    // if (reserved.len != init_regions_count) {
    //     allocator.rawFree(@ptrCast(reserved), .fromByteUnits(requested_align), 0);
    // }

    for (memory[0..memory_count]) |region| {
        if (region.type != .usable and region.type != .no_alloc) continue;
        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);

        const region_end = region.base + region.len;
        var base = region.base;
        while (base < region_end) {
            var free_end: hal_page.PhysAddr = region_end;
            var covered_end: ?hal_page.PhysAddr = null;
            for (reserved[0..reserved_count]) |rsvd_region| {
                if (rsvd_region.len == 0) continue;
                const rsvd_base = rsvd_region.base;
                const rsvd_end = rsvd_base + rsvd_region.len;
                if (rsvd_end <= base or rsvd_base >= region_end) continue;
                if (rsvd_base <= base) {
                    const end = @min(rsvd_end, region_end);
                    covered_end = if (covered_end) |e| @max(e, end) else end;
                } else {
                    free_end = @min(free_end, rsvd_base);
                }
            }
            if (covered_end) |end| {
                base = end;
                continue;
            }
            if (free_end > base) {
                buddy.add(
                    @truncate(base >> hal_page.page_shift),
                    (free_end - base) / hal_page.page_size,
                );
            }
            base = free_end;
        }
    }
}

/// Map all memory into direct mapping area
pub fn makeDirectMap(page_table: mem.page_table.PageTablePtr) !void {
    var base: hal_page.PhysAddr = memory[0].base;
    var len: usize = 0;

    var usable_mem: usize = 0;
    var reserved_mem: usize = 0;

    memory[memory_count] = sentinel_region;
    for (memory[0 .. memory_count + 1]) |region| {
        // log.debug(
        //     @src(),
        //     "memory: 0x{x} - 0x{x}",
        //     .{ region.base, region.base + region.len },
        // );
        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);

        if (region.type == .no_map) {
            reserved_mem += region.len;
            continue;
        }
        usable_mem += region.len;

        if (base + len != region.base) {
            // log.debug(@src(), "mapped memory: 0x{x} - 0x{x}", .{ base, base + len });
            try page_table.mapRange(
                allocator,
                base + hal_page.direct_map_base,
                base,
                len / hal_page.page_size,
                .{
                    .writable = true,
                    .executable = false,
                    .userspace = false,
                    .global = true,
                    .cache_policy = .write_back,
                },
            );

            base = region.base;
            len = region.len;
        } else {
            len += region.len;
        }
    }

    log.info(@src(), "Total memory: {Bi}", .{usable_mem + reserved_mem});
    log.info(@src(), "Usable memory: {Bi}", .{usable_mem});
    log.info(@src(), "Reserved memory: {Bi}", .{reserved_mem});
}

/// Create and map page metadata area
pub fn makePageMetadata(page_table: mem.page_table.PageTablePtr) !void {
    var max_paddr: hal_page.PhysAddr = 0;
    for (memory[0..memory_count]) |region| {
        if (region.type != .usable and region.type != .no_alloc) continue;

        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);

        max_paddr = @max(max_paddr, region.base + region.len);
    }

    const matadata_num = max_paddr / hal_page.page_size;
    const metadata_size = std.mem.alignForward(
        hal_page.VirtAddr,
        matadata_num * @sizeOf(mem.page.PageMeta),
        hal_page.page_size,
    );
    const metadata = blk: inline for ([_]hal_page.PageLevel{ .level2, .level1 }) |level| {
        if (level.pageSize()) |page_size| {
            if (allocator.alignedAlloc(
                u8,
                .fromByteUnits(page_size),
                metadata_size,
            )) |metamem| {
                break :blk metamem;
            } else |err| {
                if (level == .level1) {
                    return err;
                }
            }
        }
    };
    @memset(metadata, 0);
    try page_table.mapRange(
        allocator,
        hal_page.page_meta_base,
        @intFromPtr(metadata.ptr) - hal_page.direct_map_base,
        metadata_size / hal_page.page_size,
        .{
            .writable = true,
            .executable = false,
            .userspace = false,
            .global = true,
            .cache_policy = .write_back,
        },
    );

    // log.debug(
    //     @src(),
    //     "Page metadata: 0x{x} - 0x{x} ({Bi})",
    //     .{ hal_page.page_meta_base, hal_page.page_meta_base + metadata_size, metadata_size },
    // );
}

fn update(array: *[]Region, count: *usize, base: hal_page.PhysAddr, len: usize, @"type": RegionType) Allocator.Error!void {
    if (count.* + 4 >= array.len and !is_expanding) {
        is_expanding = true;
        // Expand
        const new_arr = try allocator.alignedAlloc(
            Region,
            .fromByteUnits(requested_align),
            array.len * 2,
        );
        @memcpy(new_arr[0..array.len], array.*);
        // Allocator.free will use array.*
        // So we should update it first, then free old_arr
        const old_arr = array.*;
        array.* = new_arr;
        if (old_arr.len != init_regions_count) {
            allocator.free(old_arr);
        }
        // log.debug(@src(), "expanded", .{});
        is_expanding = false;
    }
    assert(array.len > count.*);
    array.*[count.*] = .{
        .base = base,
        .len = len,
        .type = @"type",
    };
    count.* += 1;
}
/// Mamory should align to page_size
pub inline fn add(base: hal_page.PhysAddr, len: usize, @"type": RegionType) Allocator.Error!void {
    assert(base % hal_page.page_size == 0);
    assert(len % hal_page.page_size == 0);
    // log.debug(@src(), "add {s}: 0x{x} - 0x{x}", .{ @tagName(@"type"), base, base + len });
    try update(&memory, &memory_count, base, len, @"type");
}
pub inline fn reserve(base: hal_page.PhysAddr, len: usize) Allocator.Error!void {
    try update(&reserved, &reserved_count, base, len, .occupied);
}

fn isReserved(base: hal_page.PhysAddr, len: usize) bool {
    for (reserved[0..reserved_count]) |region| {
        if (region.len == 0) continue;
        if (base < region.base + region.len and base + len > region.base) {
            return true;
        }
    }
    return false;
}
/// alloc() ensures reserved_region are contained by memory_region
fn alloc(len: usize, @"align": usize) ?hal_page.PhysAddr {
    for (memory[0..memory_count]) |region| {
        if (region.type != .usable) continue;
        var base = std.mem.alignForward(hal_page.PhysAddr, region.base, @"align");
        while (base + len <= region.base + region.len) {
            if (!isReserved(base, len)) {
                return if (reserve(base, len)) base else |_| null;
            }
            base += @"align";
        }
    }
    return null;
}
fn free(base: hal_page.PhysAddr, len: usize) void {
    // log.debug(@src(), "free: 0x{x} {}", .{ base, len });
    for (reserved[0..reserved_count]) |*region| {
        // log.debug(@src(), "region: 0x{x} {}", .{ region.base, region.len });
        if (region.base == base and region.len == len) {
            region.* = .{ .base = 0, .len = 0, .type = .no_map };
            return;
        }
    }
    @panic("Bad free");
}

/// Memory alloc/free must align to page_size
pub const allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};
const vtable: Allocator.VTable = .{
    .alloc = allocFunc,
    .free = freeFunc,
    .remap = Allocator.noRemap,
    .resize = Allocator.noResize,
};
fn allocFunc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    if (alloc(len, alignment.toByteUnits())) |base| {
        // log.debug(@src(), "alloc: 0x{x} - 0x{x}", .{ base, base + len });
        return @ptrFromInt(base + hal_page.direct_map_base);
    } else {
        return null;
    }
}
fn freeFunc(_: *anyopaque, slice: []u8, _: std.mem.Alignment, _: usize) void {
    const base = @intFromPtr(slice.ptr);
    assert(base >= hal_page.direct_map_base);
    assert(base < hal_page.direct_map_base + hal_page.direct_map_size);
    free(base - hal_page.direct_map_base, slice.len);
}
