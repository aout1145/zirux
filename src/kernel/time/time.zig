const std = @import("std");
const root = @import("root");
const hal = root.hal;

const tick = @import("tick.zig");

var sync_count: std.atomic.Value(hal.cpu.CpuId) = .init(0);
pub fn init() !void {
    _ = sync_count.fetchAdd(1, .acq_rel);
    while (sync_count.load(.acquire) != hal.cpu.getCpuList().len) {
        hal.cpu.spinHint();
    }

    try tick.init();
}

pub const jiffies = tick.jiffies;
