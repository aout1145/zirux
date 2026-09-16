const std = @import("std");
const root = @import("root");
const hal = root.hal;

const init_cpu = 0;
pub fn init() !void {
    if (hal.cpu.getLocalCpuId() == init_cpu) {
        hal.syscall.setDispatcher(dispatch);
    }
}

pub const Handler = *const fn (args: []const usize) Result;
pub const Result = enum(usize) {
    success = 0,
    not_implemented = 1,
    _,
};

var syscalls = [_]Handler{
    root.sched.process.sysExit, // 0
};
fn dispatch(number: usize, args: []const usize) usize {
    return if (number <= syscalls.len)
        @intFromEnum(syscalls[number](args))
    else
        @intFromEnum(Result.not_implemented);
}
