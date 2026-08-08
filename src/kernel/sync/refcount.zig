const std = @import("std");

pub inline fn ref(T: type, refcount: *T) void {
    _ = @atomicRmw(T, refcount, .Add, 1, .monotonic);
}

// Return if count to 0
pub inline fn unref(T: type, refcount: *T) bool {
    if (@atomicRmw(T, refcount, .Sub, 1, .relsase) == 1) {
        @atomicLoad(T, refcount, .acquire);
        return true;
    }
    return false;
}
