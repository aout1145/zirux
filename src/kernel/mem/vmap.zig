const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const assert = std.debug.assert;
const hal = root.hal;
const gpa = root.mem.general_allocator;

const Area = struct {
    node: std.DoublyLinkedList.Node,
    /// Base virtual address
    base: hal.page.VirtAddr,
    /// Number of pages
    len: usize,
    /// Physical pages
    pages: []hal.page.PageIndex,
};
var vmap_lock: root.sync.SpinLockIrq = .unlocked;
var free_list: std.DoublyLinkedList = .{};
var allocated_list: std.DoublyLinkedList = .{};

pub const VMapError = error{
    OutOfMemory,
};

fn map(pages: []hal.page.PageIndex, attr: hal.page.PageAttribute) VMapError!hal.page.VirtAddr {
    const vmap_flag = vmap_lock.lock();
    defer vmap_lock.unlock(vmap_flag);

    if (free_list.first == null and allocated_list.first == null) {
        // Initialize.
        const area = try gpa.create(Area);
        area.base = hal.page.virtual_map_base;
        area.len = hal.page.virtual_map_size / hal.page.page_size;
        free_list.append(&area.node);
    }

    if (free_list.first == null)
        return VMapError.OutOfMemory;

    var node = free_list.first.?;
    while (true) {
        const area: *Area = @fieldParentPtr("node", node);
        if (pages.len <= area.len) {
            errdefer @panic("TODO");
            {
                var kpt_flag: u8 = undefined;
                const pt = root.mem.page_table.getKernelPageTable(&kpt_flag);
                defer root.mem.page_table.releaseKernelPageTable(kpt_flag);
                for (pages, 0..) |page_index, i| {
                    try pt.map(
                        gpa,
                        .level1,
                        area.base + i * hal.page.page_size,
                        hal.page.index2addr(page_index),
                        attr,
                    );
                }
            }
            {
                if (pages.len < area.len) {
                    const free_area = try gpa.create(Area);
                    free_area.base = area.base + pages.len * hal.page.page_size;
                    free_area.len = area.len - pages.len;
                    free_list.append(&free_area.node);
                }
                area.len = pages.len;
                area.pages = pages;
                free_list.remove(&area.node);
                allocated_list.append(&area.node);
            }
            return area.base;
        }

        node = node.next orelse break;
    }
    return VMapError.OutOfMemory;
}

pub fn ioMap(addr: hal.page.PhysAddr, len: usize, cache_policy: hal.page.CachePolicy) VMapError!*hal.io.IoMem {
    const index_start: hal.page.PageIndex = @intCast(addr / hal.page.page_size);
    const index_end: hal.page.PageIndex = @intCast((addr + len + hal.page.page_size - 1) / hal.page.page_size);
    const pages = try gpa.alloc(hal.page.PageIndex, index_end - index_start);
    for (pages, 0..) |*page_index, i| {
        page_index.* = @intCast(index_start + i);
    }
    const vaddr = try map(pages, .{
        .writable = true,
        .executable = false,
        .userspace = false,
        .global = true,
        .cache_policy = cache_policy,
    });
    return @ptrFromInt(vaddr + addr - hal.page.index2addr(index_start));
}
