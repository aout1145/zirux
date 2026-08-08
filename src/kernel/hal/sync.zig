const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub inline fn spinLockIrq() u8 {
    return arch.sync.spinLockIrq();
}
pub inline fn spinUnlockIrq(flag: u8) void {
    arch.sync.spinUnlockIrq(flag);
}
pub inline fn spinHint() void {
    arch.sync.spinHint();
}
