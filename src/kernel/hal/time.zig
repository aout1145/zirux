const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

/// Thread-safe
pub const TimerDevice = struct {
    handler: ?Handler,
    vtable: *const VTable,

    pub const Handler = *const fn (*hal.context.Context, timer: *TimerDevice) void;
    pub inline fn setPeriodic(self: *TimerDevice, ms: u64) void {
        self.vtable.setPeriodic(self, ms);
    }
    pub inline fn setOneshot(self: *TimerDevice, ms: u64) void {
        self.vtable.setOneshot(self, ms);
    }
    pub inline fn shutdown(self: *TimerDevice) void {
        self.vtable.shutdown(self);
    }

    pub const VTable = struct {
        setPeriodic: *const fn (self: *TimerDevice, ms: u64) void,
        setOneshot: *const fn (self: *TimerDevice, ms: u64) void,
        shutdown: *const fn (self: *TimerDevice) void,
    };
};
/// Should disable preempt
pub inline fn getTickDevice() *TimerDevice {
    return arch.time.getTickDevice();
}

/// Thread-safe
pub const ClockSource = struct {
    vtable: *const VTable,

    pub inline fn getHz(self: *const ClockSource) u64 {
        return self.vtable.getHz(self);
    }
    pub inline fn getClock(self: *const ClockSource) u64 {
        return self.vtable.getClock(self);
    }

    pub const VTable = struct {
        getHz: *const fn (self: *const ClockSource) u64,
        getClock: *const fn (self: *const ClockSource) u64,
    };
};
