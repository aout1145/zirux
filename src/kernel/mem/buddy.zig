// Buddy Page Allocator

const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const PageMeta = root.mem.page.PageMeta;
const PageType = root.mem.page.PageType;
const PageIndex = root.hal.page.PageIndex;
const getMeta = root.mem.page.getMeta;
const sync = root.sync;

pub const max_order: u8 = 12;
var free_list: [max_order + 1]?PageIndex = .{null} ** (max_order + 1);
var max_page_index: PageIndex = undefined;
/// NOTE: When buddy_lock acquired, all PageMeta owned by Buddy are no need to lock
var buddy_lock: sync.SpinLockIrq = .unlocked;

/// NOTE: Return the number of pages
pub inline fn orderSize(order: u8) PageIndex {
    return (@as(PageIndex, 1) << @intCast(order));
}
inline fn getBuddy(order: u8, index: PageIndex) ?PageIndex {
    assert(index % orderSize(order) == 0);
    const buddy_index = index ^ orderSize(order);
    if (order != max_order and buddy_index < max_page_index) {
        const buddy_meta = getMeta(buddy_index);
        if (buddy_meta.atomicIsType(.buddy) and buddy_meta.compound.order == order) {
            return buddy_index;
        }
    }
    return null;
}

/// Should not be called except by bootmm
/// NOTE: Single-threaded
pub fn init(max_index: PageIndex) void {
    max_page_index = max_index;
}
/// Should not be called except by bootmm
/// NOTE: Single-threaded
pub fn add(start: PageIndex, num_of_pages: usize) void {
    var index = start;
    while (index != start + num_of_pages) {
        var order: u8 = max_order;
        while (true) : (order -= 1) {
            if (index % orderSize(order) == 0 and index + orderSize(order) <= start + num_of_pages) {
                const meta = getMeta(index);
                assert(meta.type == .unavailable);
                meta.type = .buddy;
                addFreeList(order, index, true);
                index += orderSize(order);
                break;
            }
        }
    }
}

/// NOTE: Must acquire buddy_lock before call
fn addFreeList(order: u8, index: PageIndex, merge: bool) void {
    assert(index % orderSize(order) == 0);
    // log.debug(@src(), "add: 0x{x} (order {})", .{ index, order });

    const meta = getMeta(index);
    assert(meta.type == .buddy);
    meta.compound = .{
        .order = order,
        .head = index,
    };
    if (free_list[order]) |next_index| {
        meta.list.setNext(next_index);
        meta.list.setPrev(null);

        const next_meta = getMeta(next_index);
        next_meta.list.setPrev(index);
    } else {
        meta.list.setNext(null);
        meta.list.setPrev(null);
    }
    free_list[order] = index;

    // Try merge free pages
    if (merge) {
        if (getBuddy(order, index)) |buddy_index| {
            // log.debug(
            //     @src(),
            //     "merge: 0x{x}, 0x{x} (order {} -> {})",
            //     .{ index, buddy_index, order, order + 1 },
            // );
            removeFreeList(index);
            removeFreeList(buddy_index);
            addFreeList(order + 1, index & buddy_index, true);
            return;
        }
    }
    // Otherwise update tail pages
    for (1..orderSize(order)) |n| {
        const tail_meta = getMeta(@intCast(index + n));
        tail_meta.type = .tail;
        tail_meta.compound = .{
            .order = order,
            .head = index,
        };
    }
}
/// NOTE: Must acquire buddy_lock before call
fn removeFreeList(index: PageIndex) void {
    const meta = getMeta(index);
    assert(meta.type == .buddy);
    if (meta.list.next()) |next_index| {
        const next_meta = getMeta(next_index);
        next_meta.list.setPrev(meta.list.prev());
    }
    if (meta.list.prev()) |prev_index| {
        const prev_meta = getMeta(prev_index);
        prev_meta.list.setNext(meta.list.next());
    } else {
        // First node, so we update free_list
        free_list[meta.compound.order] = meta.list.next();
    }
    meta.list.setNext(null);
    meta.list.setPrev(null);
}

pub fn alloc(order: u8, @"type": PageType) ?PageIndex {
    const buddy_flag = buddy_lock.lock();
    defer buddy_lock.unlock(buddy_flag);

    if (free_list[order] == null) {
        var current_order = order;
        while (current_order <= max_order) : (current_order += 1) {
            if (free_list[current_order] != null) break;
            if (current_order == max_order) return null;
        }
        while (current_order > order) : (current_order -= 1) {
            const index = free_list[current_order].?;
            removeFreeList(index);
            const left_index = index;
            const right_index = index ^ orderSize(current_order - 1);
            assert(getMeta(left_index).type == .buddy);
            addFreeList(current_order - 1, left_index, false);
            assert(getMeta(right_index).type == .tail);
            getMeta(right_index).type = .buddy;
            addFreeList(current_order - 1, right_index, false);
        }
    }

    const page_index = free_list[order].?;
    removeFreeList(page_index);

    const meta = getMeta(page_index);
    meta.type = @"type";
    meta._refcount = 1;
    meta.list.setNext(null);
    meta.list.setPrev(null);

    return page_index;
}

pub fn ref(page_index: PageIndex) void {
    const meta = getMeta(page_index);
    sync.ref(u32, &meta._refcount);
}

pub fn unref(page_index: PageIndex) void {
    const meta = getMeta(page_index);
    if (sync.unref(u32, &meta._refcount)) {
        const buddy_flag = buddy_lock.lock();
        defer buddy_lock.unlock(buddy_flag);

        const meta_flag = meta.lock();
        assert(meta.type != .unavailable);
        meta.type = .buddy;
        meta.unlock(meta_flag);
        addFreeList(meta.compound.order, page_index, true);
    }
}

pub fn printFreeMem() void {
    const buddy_flag = buddy_lock.lock();
    defer buddy_lock.unlock(buddy_flag);

    var order = max_order;
    var total_cnt: usize = 0;
    while (true) : (order -= 1) {
        var cnt: usize = 0;
        if (free_list[order]) |first_node| {
            var node = first_node;
            cnt += 1;
            while (getMeta(node).list.next()) |next_node| : (node = next_node) {
                cnt += 1;
            }
        }
        total_cnt += cnt * orderSize(order);
        log.debug(@src(), "Order {}: {}", .{ order, cnt });

        if (order == 0) break;
    }
    log.debug(@src(), "Total free memory: {Bi}", .{total_cnt * root.hal.page.page_size});
}
