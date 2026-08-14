const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub const IoMem = opaque {
    pub inline fn read(self: *const IoMem, T: type, offset: u64) T {
        return arch.mem.io.read(T, @intFromPtr(self) + offset);
    }
    pub inline fn write(self: *IoMem, T: type, offset: u64, val: T) void {
        arch.mem.io.write(T, @intFromPtr(self) + offset, val);
    }
};
