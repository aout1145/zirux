const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub const cache_line = arch.cpu.cache_line;
