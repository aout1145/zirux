const std = @import("std");
const root = @import("root");
const hal = root.hal;
const arch = root.arch.x86_64;

pub const lapic_timer = @import("lapic_timer.zig");

pub fn init() !void {
    try lapic_timer.init();
}

pub inline fn getTickDevice() *hal.time.TimerDevice {
    return arch.cpu.per_cpu.ptr(hal.time.TimerDevice, &lapic_timer.apic_timer);
}
