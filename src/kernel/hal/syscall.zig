const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

pub const Dispatcher = *const fn (number: usize, args: []const usize) usize;
pub inline fn setDispatcher(dispatcher: Dispatcher) void {
    arch.syscall.setDispatcher(dispatcher);
}
