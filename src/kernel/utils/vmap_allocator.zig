const std = @import("std");
const root = @import("root");
const hal = root.hal;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// NOTE: Thread-safe
pub fn VMapAllocator(Data: type) type {
    return struct {
        const Self = @This();

        pub const Area = struct {
            /// Base virtual address
            base: hal.page.VirtAddr,
            /// Number of pages
            pages_num: usize,
        };

        init_area: Area,
        vmap_lock: root.sync.SpinLockIrq,
        free_list: std.ArrayList(Area),
        allocated_list: std.ArrayList(Area),
        page_data: std.AutoHashMapUnmanaged(hal.page.VirtAddr, Data),

        pub fn init(init_area: Area) Self {
            return .{
                .init_area = init_area,
                .vmap_lock = .unlocked,
                .free_list = .empty,
                .allocated_list = .empty,
                .page_data = .empty,
            };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            const lock_flag = self.vmap_lock.lock();
            defer self.vmap_lock.unlock(lock_flag);

            self.free_list.deinit(gpa);
            self.allocated_list.deinit(gpa);
            self.page_data.deinit(gpa);
        }

        pub const AllocateError = error{
            OutOfMemory,
            NoFreeSpace,
        };
        pub fn alloc(
            self: *Self,
            gpa: Allocator,
            pages_num: usize,
            data: Data,
            vaddr: ?hal.page.VirtAddr,
        ) AllocateError!hal.page.VirtAddr {
            const lock_flag = self.vmap_lock.lock();
            defer self.vmap_lock.unlock(lock_flag);

            if (self.free_list.items.len == 0 and self.allocated_list.items.len == 0) {
                try self.free_list.append(gpa, self.init_area);
            }

            assert(pages_num != 0);
            try self.allocated_list.ensureUnusedCapacity(gpa, 1);
            try self.free_list.ensureUnusedCapacity(gpa, 1);
            try self.page_data.ensureUnusedCapacity(gpa, 1);
            if (vaddr) |base| {
                assert(base % hal.page.page_size == 0);
                for (self.free_list.items, 0..) |*free_area, i| {
                    if (free_area.base <= base and
                        free_area.base + free_area.pages_num * hal.page.page_size >= base + pages_num * hal.page.page_size)
                    {
                        self.allocated_list.appendAssumeCapacity(.{
                            .base = base,
                            .pages_num = pages_num,
                        });
                        self.page_data.putAssumeCapacityNoClobber(base, data);

                        const free_pages_num_front = @divExact(base - free_area.base, hal.page.page_size);
                        const free_pages_num_back = free_area.pages_num - free_pages_num_front - pages_num;
                        if (free_pages_num_back != 0) {
                            self.free_list.appendAssumeCapacity(.{
                                .base = base + hal.page.page_size * pages_num,
                                .pages_num = free_pages_num_back,
                            });
                        }
                        if (free_pages_num_front != 0) {
                            free_area.pages_num = free_pages_num_front;
                        } else {
                            _ = self.free_list.swapRemove(i);
                        }

                        return base;
                    }
                }
            } else {
                for (self.free_list.items, 0..) |*free_area, i| {
                    if (free_area.pages_num >= pages_num) {
                        const allocated_base = free_area.base;
                        self.allocated_list.appendAssumeCapacity(.{
                            .base = allocated_base,
                            .pages_num = pages_num,
                        });
                        self.page_data.putAssumeCapacityNoClobber(free_area.base, data);

                        free_area.base += hal.page.page_size * pages_num;
                        free_area.pages_num -= pages_num;
                        if (free_area.pages_num == 0) {
                            _ = self.free_list.swapRemove(i);
                        }
                        return allocated_base;
                    }
                }
            }
            return AllocateError.NoFreeSpace;
        }

        pub const FreeError = error{
            OutOfMemory,
            InvalidAddress,
        };
        pub fn free(
            self: *Self,
            gpa: Allocator,
            base: hal.page.VirtAddr,
        ) FreeError!void {
            const lock_flag = self.vmap_lock.lock();
            defer self.vmap_lock.unlock(lock_flag);

            if (self.page_data.get(base) == null)
                return FreeError.InvalidAddress;

            try self.free_list.ensureUnusedCapacity(gpa, 1);
            for (self.allocated_list.items, 0..) |allocated_area, i| {
                if (allocated_area.base == base) {
                    self.free_list.appendAssumeCapacity(allocated_area);
                    _ = self.allocated_list.swapRemove(i);
                    assert(self.page_data.remove(base));
                    return;
                }
            }
            return FreeError.InvalidAddress;
        }

        pub const Iterator = struct {
            self: *Self,
            index: usize,
            lock_flag: u8,

            pub fn next(iter: *Iterator) ?Area {
                if (iter.index >= iter.self.allocated_list.items.len) {
                    return null;
                } else {
                    const area = iter.self.allocated_list.items[iter.index];
                    iter.index += 1;
                    return area;
                }
            }
            pub fn deinit(iter: *Iterator) void {
                iter.self.vmap_lock.unlock(iter.lock_flag);
            }
        };
        /// Iterator should deinit
        pub inline fn iterator(self: *Self) Iterator {
            return .{
                .self = self,
                .index = 0,
                .lock_flag = self.vmap_lock.lock(),
            };
        }
    };
}
