pub const x86_64 = @import("x86_64/arch.zig");

pub const target = switch (@import("builtin").cpu.arch) {
    .x86_64 => x86_64,
    else => @compileError("Unsupported CPU Architecture!"),
};
