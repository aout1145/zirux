const std = @import("std");
const root = @import("root");
const hal = root.hal;
const log = root.debug.log;

const hz = 100;
const jiffies_cpu = 0;
var jiffies_count: std.atomic.Value(u64) = .init(0);

pub fn init() !void {
    root.sched.preemptDisable();
    defer root.sched.preemptEnable();

    const tick_device = hal.time.getTickDevice();
    tick_device.handler = if (hal.cpu.getLocalCpuId() == jiffies_cpu) jiffiesHandler else handler;
    tick_device.setPeriodic(1000 / hz);
}

fn jiffiesHandler(ctx: *hal.context.Context, timer: *hal.time.TimerDevice) void {
    _ = jiffies_count.fetchAdd(1, .monotonic);
    // log.debug(@src(), "{}", .{jiffies.getCount()});
    handler(ctx, timer);
}
fn handler(ctx: *hal.context.Context, timer: *hal.time.TimerDevice) void {
    _ = ctx;
    _ = timer;
    root.sched.setRescheduleFlag();
}

const jiffies_vtable: hal.time.ClockSource.VTable = .{
    .getStatus = getStatus,
    .setStatus = setStatus,
    .getHz = getHz,
    .getCount = getCount,
};
fn getStatus(_: *const hal.time.ClockSource) hal.time.ClockSource.Status {
    return .running;
}
fn setStatus(_: *hal.time.ClockSource, status: hal.time.ClockSource.Status) void {
    if (status == .stopped)
        unreachable;
}
fn getHz(_: *const hal.time.ClockSource) u64 {
    return hz;
}
fn getCount(_: *const hal.time.ClockSource) u64 {
    return jiffies_count.load(.monotonic);
}
pub const jiffies: hal.time.ClockSource = .{
    .vtable = &jiffies_vtable,
};
