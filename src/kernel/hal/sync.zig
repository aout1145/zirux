const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub inline fn spinHint() void {
    arch.sync.spinHint();
}
