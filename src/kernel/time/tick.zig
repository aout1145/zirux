const std = @import("std");
const root = @import("root");
const hal = root.hal;
const log = root.debug.log;

const hz = 100;
const jiffies_cpu = 0;
var jiffies_count: std.atomic.Value(u64) = .init(0);

pub fn init() !void {
    hal.sched.preemptDisable();
    defer hal.sched.preemptDisable();

    const tick_device = hal.time.getTickDevice();
    tick_device.handler = if (hal.cpu.getLocalCpuId() == jiffies_cpu) jiffiesHandler else handler;
    tick_device.setPeriodic(1000 / hz);
}

fn jiffiesHandler(ctx: *hal.context.Context, timer: *hal.time.TimerDevice) void {
    _ = jiffies_count.fetchAdd(1, .monotonic);
    handler(ctx, timer);
}
fn handler(ctx: *hal.context.Context, timer: *hal.time.TimerDevice) void {
    _ = ctx;
    _ = timer;
    root.sched.thread.schedule();
    // log.debug(@src(), "{}", .{jiffies.getClock()});
}

const jiffies_vtable: hal.time.ClockSource.VTable = .{
    .getHz = getHz,
    .getClock = getClock,
};
fn getHz(_: *const hal.time.ClockSource) u64 {
    return hz;
}
fn getClock(_: *const hal.time.ClockSource) u64 {
    return jiffies_count.load(.monotonic);
}
pub const jiffies: hal.time.ClockSource = .{
    .vtable = &jiffies_vtable,
};
