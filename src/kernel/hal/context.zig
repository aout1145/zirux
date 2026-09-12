const std = @import("std");
const root = @import("root");
const hal = root.hal;
const arch = root.arch.target;

pub const Context = opaque {
    pub inline fn format(self: *const Context, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try arch.cpu.context.Context.format(@ptrCast(@alignCast(self)), writer);
    }
};

pub const StackPointer = hal.page.PhysAddr;
