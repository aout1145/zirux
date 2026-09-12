const std = @import("std");
const root = @import("root");
const hal = root.hal;

pub const thread = @import("thread.zig");
pub const process = @import("process.zig");

pub fn init() !void {
    try process.init();
    hal.sched.preemptEnable();
}
