pub const gdt = @import("gdt.zig");
pub const per_cpu = @import("per_cpu.zig");
pub const context = @import("context.zig");

pub const cache_line: usize = 64;
