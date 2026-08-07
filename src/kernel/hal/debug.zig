const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub const print = arch.debug.print;
pub const panicFn = arch.debug.panic;
