const std = @import("std");
const root = @import("root");
const hal_sync = root.hal.sync;

pub const SpinLock = enum(u8) {
    unlocked = 0,
    locked = 1,
    pub const Flag = u8;
    pub fn lock(self: *SpinLock) Flag {
        const flag = hal_sync.spinLockIrq();
        while (@cmpxchgWeak(
            SpinLock,
            self,
            .unlocked,
            .locked,
            .acquire,
            .monotonic,
        ) != null) {
            hal_sync.spinHint();
        }
        return flag;
    }
    pub fn unlock(self: *SpinLock, flag: Flag) void {
        @atomicStore(SpinLock, self, .unlocked, .release);
        hal_sync.spinUnlockIrq(flag);
    }
};
