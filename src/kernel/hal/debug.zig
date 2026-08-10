const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub const println = arch.debug.println;
pub const panicFn = arch.debug.panic;
