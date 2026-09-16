const std = @import("std");
const root = @import("root");
const hal = root.hal;

pub const SpinLockIrq = enum(u8) {
    unlocked = 0,
    locked = 1,
    pub const Flag = u8;
    pub fn lock(self: *SpinLockIrq) Flag {
        const flag = hal.intr.irqSave();
        root.sched.preemptDisable();
        while (@cmpxchgWeak(
            SpinLockIrq,
            self,
            .unlocked,
            .locked,
            .acquire,
            .monotonic,
        ) != null) {
            hal.sync.spinHint();
        }
        return flag;
    }
    pub fn unlock(self: *SpinLockIrq, flag: Flag) void {
        @atomicStore(SpinLockIrq, self, .unlocked, .release);
        root.sched.preemptEnable();
        hal.intr.irqRestore(flag);
    }
};
