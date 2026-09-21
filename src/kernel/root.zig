const std = @import("std");

// Debug
pub const debug = @import("debug/debug.zig");
pub const std_options_debug_io = std.Io.failing;
pub const panic = hal.debug.panicFn;

/// NOTE: Not use except architecture-related code.
///       Consider use HAL.
pub const arch = @import("arch/arch.zig");

// Modules
pub const hal = @import("hal/hal.zig");
pub const mem = @import("mem/mem.zig");
pub const sync = @import("sync/sync.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const time = @import("time/time.zig");
pub const sched = @import("sched/sched.zig");
pub const utils = @import("utils/utils.zig");
pub const fs = @import("fs/fs.zig");
pub const syscall = @import("syscall/syscall.zig");

// Kernel main
pub const kernelMain = @import("main.zig").kernelMain;

// Kernel entry
export const _start = hal._start;
