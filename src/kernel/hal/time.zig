const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

pub const TimerDevice = struct {
    handler: ?Handler,
    vtable: *const VTable,

    pub const Handler = *const fn (*hal.context.Context) void;
    pub inline fn setPeriodic(self: *TimerDevice, ms: u64) void {
        self.vtable.setPeriodic(self, ms);
    }
    pub inline fn setOneshot(self: *TimerDevice, ms: u64) void {
        self.vtable.setOneshot(self, ms);
    }

    pub const VTable = struct {
        setPeriodic: *const fn (self: *TimerDevice, ms: u64) void,
        setOneshot: *const fn (self: *TimerDevice, ms: u64) void,
    };
};
