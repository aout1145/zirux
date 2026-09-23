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

    pub const Status = enum {
        running,
        stopped,
    };
    pub inline fn getStatus(self: *const ClockSource) Status {
        return self.vtable.getStatus(self);
    }
    pub inline fn setStatus(self: *ClockSource, status: Status) void {
        return self.vtable.setStatus(self, status);
    }
    pub inline fn getHz(self: *const ClockSource) u64 {
        return self.vtable.getHz(self);
    }
    pub inline fn getCount(self: *const ClockSource) u64 {
        return self.vtable.getCount(self);
    }

    pub const VTable = struct {
        getStatus: *const fn (self: *const ClockSource) Status,
        setStatus: *const fn (self: *ClockSource, status: Status) void,
        getHz: *const fn (self: *const ClockSource) u64,
        getCount: *const fn (self: *const ClockSource) u64,
    };
};
