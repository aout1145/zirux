const std = @import("std");
const root = @import("root");
const hal = root.hal;

pub const tick_hz = 200;
pub const tick_ms = 1000 / tick_hz;

pub fn handler(ctx: *hal.context.Context) void {
    _ = ctx;
}
