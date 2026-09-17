const std = @import("std");
const root = @import("root");
const hal = root.hal;

/// NOTE: Thread-safe
const VMapAllocator = struct {
    pub const Area = struct {
        node: std.DoublyLinkedList.Node,
        /// Base virtual address
        base: hal.page.VirtAddr,
        /// Number of pages
        pages_num: usize,
        attr: hal.page.PageAttribute,
    };

    vmap_lock: root.sync.SpinLockIrq,
    free_list: std.DoublyLinkedList,
    allocated_list: std.DoublyLinkedList,

    pub const AllocateError = error{
        NoFreeArea,
    };
    pub fn alloc(pages_num: usize) AllocateError!Area {
        _ = pages_num;
        @panic("TODO");
    }
};
