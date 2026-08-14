const std = @import("std");

// Debug
pub const debug = @import("debug/debug.zig");
pub const std_options_debug_io = std.Io.failing;
pub const panic = hal.debug.panicFn;

// Modules
/// NOTE: Not use except architecture-related code.
///       Consider use HAL.
pub const arch = @import("arch/arch.zig");
pub const hal = @import("hal/hal.zig");
pub const mem = @import("mem/mem.zig");
pub const sync = @import("sync/sync.zig");
pub const intr = @import("intr/intr.zig");
pub const drivers = @import("drivers/drivers.zig");

// Kernel entry
export const _start = hal._start;
