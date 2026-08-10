const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;

pub inline fn spinHint() void {
    arch.@"asm".pause();
}
