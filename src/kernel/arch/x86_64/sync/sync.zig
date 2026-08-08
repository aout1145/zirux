const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;

pub inline fn spinLockIrq() u8 {
    const rflags = arch.@"asm".readRflags();
    asm volatile ("cli");
    return @intFromBool(rflags.@"if");
}
pub inline fn spinUnlockIrq(flag: u8) void {
    var rflags = arch.@"asm".readRflags();
    rflags.@"if" = (flag == 1);
    arch.@"asm".writeRflags(rflags);
}
pub inline fn spinHint() void {
    arch.@"asm".pause();
}
