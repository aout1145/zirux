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

pub inline fn init(stack: []u8, entry: hal.page.PhysAddr, userspace: bool) StackPointer {
    return arch.cpu.context.init(stack, entry, userspace);
}

pub inline fn switchTo(save_sp: *StackPointer, next_kernel_stack: []u8, next_sp: StackPointer) void {
    return arch.cpu.context.switchTo(save_sp, next_kernel_stack, next_sp);
}
