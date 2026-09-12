const std = @import("std");
const root = @import("root");

const tick = @import("tick.zig");

pub fn init() !void {
    try tick.init();
}

pub const jiffies = tick.jiffies;
