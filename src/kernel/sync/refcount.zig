const std = @import("std");
const assert = std.debug.assert;

pub inline fn ref(T: type, refcount: *T) void {
    assert(@atomicRmw(T, refcount, .Add, 1, .monotonic) != 0);
}

// Return if count to 0
pub inline fn unref(T: type, refcount: *T) bool {
    if (@atomicRmw(T, refcount, .Sub, 1, .release) == 1) {
        _ = @atomicLoad(T, refcount, .acquire);
        return true;
    }
    return false;
}
