// Boot Stage Memory Manager
// NOTE: Single-threaded

const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const hal_page = root.hal.page;
const mem = root.mem;
const log = root.debug.log;

var available: std.atomic.Value(bool) = .init(true);
var memory: []Region = undefined;
var memory_count: usize = 0;
var reserved: []Region = undefined;
var reserved_count: usize = 0;

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

const init_regions_count = 128;
pub const requested_size = @sizeOf(Region) * init_regions_count;
pub const requested_align = @alignOf(Region);
pub fn init(buffer: *align(requested_align) [2][requested_size]u8) void {
    memory.ptr = @ptrCast(&buffer[0]);
    memory.len = init_regions_count;
    reserved.ptr = @ptrCast(&buffer[1]);
    reserved.len = init_regions_count;
    available.store(true, .monotonic);
}
pub fn deinit() void {
    assert(available.load(.monotonic));
    if (memory.len != init_regions_count) {
        allocator.free(memory);
    }
    if (reserved.len != init_regions_count) {
        allocator.free(reserved);
    }

    available.store(false, .monotonic);
}

/// Map all memory into direct mapping area
pub fn makeDirectMap(page_table: mem.page_table.PageTable) !void {
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

        if (region.type == .no_map) {
            reserved_mem += region.len;
            continue;
        }

        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);
        usable_mem += region.len;

        if (base + len != region.base) {
            log.debug(@src(), "mapped memory: 0x{x} - 0x{x}", .{ base, base + len });
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
pub fn makePageMetadata(page_table: mem.page_table.PageTable) !void {
    var base: hal_page.PhysAddr = memory[0].base;
    var len: usize = 0;

    var used_mem: usize = 0;

    memory[memory_count] = sentinel_region;
    for (memory[0 .. memory_count + 1]) |region| {
        if (region.type == .no_map or region.type == .occupied)
            continue;

        assert(region.base % hal_page.page_size == 0);
        assert(region.len % hal_page.page_size == 0);

        if (base + len != region.base) {
            const metadata_offset = base / hal_page.page_size * @sizeOf(mem.page_table.PageMeta);
            const metadata_base = hal_page.page_meta_base + metadata_offset;
            var metadata_base_aligned = std.mem.alignBackward(
                usize,
                metadata_base,
                hal_page.page_size,
            );
            const matadata_size_raw = len / hal_page.page_size * @sizeOf(mem.page_table.PageMeta);
            const metadata_size = metadata_base - metadata_base_aligned + matadata_size_raw;
            var metadata_size_aligned = std.mem.alignForward(
                usize,
                metadata_size,
                hal_page.page_size,
            );
            // log.debug(@src(), "memory: 0x{Bi} - 0x{Bi}", .{ base, base + len });
            // log.debug(
            //     @src(),
            //     "original page metadata: 0x{x} - 0x{x}",
            //     .{ metadata_base_aligned, metadata_base_aligned + metadata_num_aligned },
            // );

            // handle overlaps
            while (page_table.query(metadata_base_aligned) != null and metadata_size_aligned != 0) {
                metadata_base_aligned += hal_page.page_size;
                metadata_size_aligned -= hal_page.page_size;
            }
            const metadata = try allocator.alignedAlloc(
                u8,
                .fromByteUnits(hal_page.page_size),
                metadata_size_aligned,
            );
            try page_table.mapRange(
                allocator,
                metadata_base_aligned,
                @intFromPtr(metadata.ptr) - hal_page.direct_map_base,
                metadata_size_aligned / hal_page.page_size,
                .{
                    .writable = true,
                    .executable = false,
                    .userspace = false,
                    .global = true,
                    .cache_policy = .write_back,
                },
            );
            used_mem += metadata_size_aligned;
            log.debug(
                @src(),
                "metadata: 0x{x} - 0x{x}",
                .{ metadata_base_aligned, metadata_base_aligned + metadata_size_aligned },
            );

            base = region.base;
            len = region.len;
        } else {
            len += region.len;
        }
    }

    log.info(@src(), "Page metadata: {Bi}", .{used_mem});
}

fn update(array: *[]Region, count: *usize, base: hal_page.PhysAddr, len: usize, @"type": RegionType) Allocator.Error!void {
    if (count.* + 4 >= array.len) {
        // Expand
        const new_arr = try allocator.alloc(Region, array.len * 2);
        @memcpy(new_arr, array.*);
        if (array.len != init_regions_count) {
            allocator.free(array.*);
        }
        array.* = new_arr;
        log.debug(@src(), "expanded", .{});
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
    assert(available.load(.monotonic));
    assert(base % hal_page.page_size == 0);
    assert(len % hal_page.page_size == 0);
    // log.debug(@src(), "add {s}: 0x{x} - 0x{x}", .{ @tagName(@"type"), base, base + len });
    try update(&memory, &memory_count, base, len, @"type");
}
inline fn reserve(base: hal_page.PhysAddr, len: usize) Allocator.Error!void {
    assert(available.load(.monotonic));
    try update(&reserved, &reserved_count, base, len, .occupied);
}

fn isReserved(base: hal_page.PhysAddr, len: usize) bool {
    for (reserved[0..reserved_count]) |region| {
        if ((base >= region.base and base < region.base + region.len) or (base + len > region.base and base + len <= region.len)) {
            return true;
        }
    }
    return false;
}
fn alloc(len: usize, @"align": usize) ?hal_page.PhysAddr {
    assert(len % hal_page.page_size == 0);
    assert(@"align" % hal_page.page_size == 0);
    for (memory[0..memory_count]) |region| {
        if (region.type != .usable) continue;
        var base = std.mem.alignForwardAnyAlign(hal_page.PhysAddr, region.base, @"align");
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
    for (reserved[0..reserved_count]) |*region| {
        if (region.base == base and region.len == len) {
            region.* = .{ .base = 0, .len = 0, .type = .no_alloc };
        }
    }
    @panic("Bad free");
}

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
    assert(available.load(.monotonic));

    if (alloc(len, alignment.toByteUnits())) |base| {
        // log.debug(@src(), "alloc: 0x{x} - 0x{x}", .{ base, base + len });
        return @ptrFromInt(base + hal_page.direct_map_base);
    } else {
        return null;
    }
}
fn freeFunc(_: *anyopaque, slice: []u8, _: std.mem.Alignment, _: usize) void {
    assert(available.load(.monotonic));

    const base = @intFromPtr(slice.ptr);
    assert(base >= hal_page.direct_map_base);
    assert(base < hal_page.direct_map_base + hal_page.direct_map_size);
    free(base - hal_page.direct_map_base, slice.len);
}
