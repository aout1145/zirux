const std = @import("std");
const root = @import("root");
const hal = root.hal;
const assert = std.debug.assert;

pub const thread = @import("thread.zig");
pub const process = @import("process.zig");

pub fn init() !void {
    try process.init();
    root.sched.preemptEnable();
}

var preempt_count: u32 linksection(hal.cpu.per_cpu_section) = 1;
pub inline fn getPreemptCount() u32 {
    return hal.cpu.this_cpu.read(u32, &preempt_count);
}
pub inline fn preemptDisable() void {
    hal.cpu.this_cpu.add(u32, &preempt_count, 1);
}
pub inline fn preemptEnable() void {
    assert(getPreemptCount() > 0);
    hal.cpu.this_cpu.sub(u32, &preempt_count, 1);
}

var need_reschedule: bool linksection(hal.cpu.per_cpu_section) = false;
pub inline fn isNeedReschedule() bool {
    return hal.cpu.this_cpu.read(bool, &need_reschedule);
}
pub inline fn setRescheduleFlag() void {
    hal.cpu.this_cpu.write(bool, &need_reschedule, true);
}
pub inline fn clearRescheduleFlag() void {
    hal.cpu.this_cpu.write(bool, &need_reschedule, false);
}
