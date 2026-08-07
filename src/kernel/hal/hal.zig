const root = @import("root");
const arch = root.arch.target;

pub const page = @import("page.zig");
pub const debug = @import("debug.zig");

pub const _start = arch.boot._start;
