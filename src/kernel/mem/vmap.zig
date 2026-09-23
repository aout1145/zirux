const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const assert = std.debug.assert;
const hal = root.hal;
const mem = root.mem;
const allocator = mem.general_allocator;
const utils = root.utils;

var vmap_allocator: utils.VMapAllocator([]hal.page.PageIndex) = .init(.{
    .base = hal.page.virtual_map_base,
    .pages_num = @divExact(hal.page.virtual_map_size, hal.page.page_size),
});

pub fn ioMap(base: hal.page.PhysAddr, len: usize, cache_policy: hal.page.CachePolicy) !hal.io.IoRegion {
    const paddr_start = std.mem.alignBackward(hal.page.PhysAddr, base, hal.page.page_size);
    const paddr_end = std.mem.alignForward(hal.page.PhysAddr, base + len, hal.page.page_size);
    const pages_num = @divExact(paddr_end - paddr_start, hal.page.page_size);

    const pages = try allocator.alloc(hal.page.PageIndex, pages_num);
    errdefer allocator.free(pages);
    for (0..pages_num) |i| {
        pages[i] = hal.page.addr2index(paddr_start + i * hal.page.page_size);
    }

    const vbase = try vmap_allocator.alloc(allocator, pages_num, pages, null);
    errdefer vmap_allocator.free(allocator, vbase) catch {};

    const pt = mem.page_table.getKernelPageTable();
    errdefer for (0..pages_num) |i| {
        const vaddr = vbase + i * hal.page.page_size;
        if (pt.query(vaddr)) |_| {
            pt.unmap(allocator, vaddr) catch {};
        }
    };
    for (0..pages_num) |i| {
        const vaddr = vbase + i * hal.page.page_size;
        const paddr = paddr_start + i * hal.page.page_size;
        try pt.map(allocator, .level1, vaddr, paddr, .{
            .writable = true,
            .executable = false,
            .userspace = false,
            .global = true,
            .cache_policy = cache_policy,
        });
    }
    return hal.io.initMemMapIo(vbase + base - paddr_start, len);
}
