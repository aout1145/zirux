const refcount = @import("refcount.zig");
const spinlock = @import("spinlock.zig");

pub const ref = refcount.ref;
pub const unref = refcount.unref;
pub const SpinLockIrq = spinlock.SpinLockIrq;
