const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

/// NOTE: Thread-safe
pub fn IdAllocator(Id: type, Value: type) type {
    assert(@typeInfo(Id) == .int);
    return struct {
        const Self = @This();

        lock: root.sync.SpinLockIrq,
        value_map: []?*Value,
        free_queue: std.Deque(Id),

        pub const empty: Self = .{ .lock = .unlocked, .value_map = &.{}, .free_queue = .empty };

        pub fn alloc(self: *Self, gpa: Allocator, init_val: Value, comptime id_field_name: ?[]const u8) !Id {
            const lock_flag = self.lock.lock();
            defer self.lock.unlock(lock_flag);

            const value = try gpa.create(Value);
            value.* = init_val;
            errdefer gpa.destroy(value);

            const id: Id = if (self.free_queue.popFront()) |id| blk: {
                self.value_map[id] = value;
                break :blk id;
            } else blk: {
                const old_len = self.value_map.len;
                const new_len = if (old_len == 0) 1 else old_len * 2;
                try self.free_queue.ensureTotalCapacity(gpa, new_len);
                self.value_map = try gpa.realloc(self.value_map, new_len);
                self.value_map[old_len] = value;
                for (old_len + 1..new_len) |id| {
                    self.value_map[id] = null;
                }
                for (old_len + 1..new_len) |id| {
                    self.free_queue.pushBack(gpa, @intCast(id)) catch unreachable;
                }
                break :blk @intCast(old_len);
            };

            if (id_field_name) |field_name| {
                @field(value.*, field_name) = id;
            }
            return id;
        }

        /// Result of `get`: holds the allocator lock together with the value.
        ///
        /// The lock is held until `unlock` is called, which guarantees the
        /// value cannot be freed by `free` while `value` is still in use
        /// (avoiding use-after-free). While the lock is held the caller must
        /// not call any other method of this allocator (`alloc`, `free`, `get`,
        /// `iterator`), otherwise it would deadlock.
        pub const LockedValue = struct {
            /// The value associated with the requested id, or null if none is
            /// allocated for it. Only valid until `unlock` is called.
            value: ?*Value,
            lock_flag: u8,
            self: *Self,

            /// Release the lock acquired by `get`. Must be called exactly once.
            pub fn unlock(self: *const LockedValue) void {
                self.self.lock.unlock(self.lock_flag);
            }
        };

        /// Get the value associated with `id`.
        ///
        /// The returned `LockedValue` keeps the allocator lock held; the caller
        /// must call `unlock` on it once it is done using `value`.
        pub fn get(self: *Self, id: Id) LockedValue {
            const lock_flag = self.lock.lock();
            return .{
                .value = if (id < self.value_map.len) self.value_map[id] else null,
                .lock_flag = lock_flag,
                .self = self,
            };
        }

        pub fn free(self: *Self, gpa: Allocator, id: Id) !void {
            const lock_flag = self.lock.lock();
            defer self.lock.unlock(lock_flag);

            assert(self.value_map[id] != null);
            gpa.destroy(self.value_map[id].?);
            self.value_map[id] = null;
            try self.free_queue.pushBack(gpa, id);
        }

        pub const Iterator = struct {
            self: *Self,
            index: usize,
            lock_flag: u8,

            pub fn next(iter: *Iterator) ?*Value {
                while (iter.index < iter.self.value_map.len) {
                    defer iter.index += 1;
                    if (iter.self.value_map[iter.index]) |value| {
                        return value;
                    }
                }
                return null;
            }
            pub fn deinit(iter: *Iterator) void {
                iter.self.lock.unlock(iter.lock_flag);
            }
        };
        pub inline fn iterator(self: *Self) Iterator {
            return .{
                .self = self,
                .index = 0,
                .lock_flag = self.lock.lock(),
            };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            const lock_flag = self.lock.lock();
            defer self.lock.unlock(lock_flag);

            for (self.value_map) |optional_value| if (optional_value) |value| {
                gpa.destroy(value);
            };
            gpa.free(self.value_map);
            self.free_queue.deinit(gpa);
        }
    };
}
