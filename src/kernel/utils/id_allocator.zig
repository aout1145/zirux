const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn IdAllocator(Id: type, Value: type) type {
    assert(@typeInfo(Id) == .int);
    return struct {
        const Self = @This();

        value_map: []?*Value,
        free_queue: std.Deque(Id),

        pub const empty: Self = .{ .value_map = &.{}, .free_queue = .empty };

        pub fn alloc(self: *Self, gpa: Allocator) !Id {
            const value = try gpa.create(Value);
            errdefer gpa.destroy(value);
            if (self.free_queue.popFront()) |id| {
                self.value_map[id] = value;
                return id;
            } else {
                const old_len = self.value_map.len;
                const new_len = if (old_len == 0) 1 else old_len * 2;
                self.value_map = try gpa.realloc(self.value_map, new_len);
                self.value_map[old_len] = value;
                for (old_len + 1..new_len) |id| {
                    self.value_map[id] = null;
                }
                for (old_len + 1..new_len) |id| {
                    try self.free_queue.pushBack(gpa, @intCast(id));
                }
                return @intCast(old_len);
            }
        }

        pub fn get(self: *const Self, id: Id) ?*Value {
            return self.value_map[id];
        }

        pub fn free(self: *Self, gpa: Allocator, id: Id) !void {
            assert(self.value_map[id] != null);
            gpa.destroy(self.value_map[id]);
            self.value_map[id] = null;
            try self.free_queue.pushBack(gpa, id);
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            for (self.value_map) |value| {
                gpa.destroy(value);
            }
            gpa.free(self.value_map);
            self.free_queue.deinit(gpa);
        }
    };
}
