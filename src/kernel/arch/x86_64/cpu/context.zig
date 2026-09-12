const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const arch = root.arch.x86_64;

pub const Context = packed struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,

    vector: u64,
    error_code: u64,
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,

    pub fn format(ctx: *const Context, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("RIP    : 0x{X:0>16}\n", .{ctx.rip});
        try writer.print("RFLAGS : 0x{X:0>16}\n", .{ctx.rflags});
        try writer.print("RAX    : 0x{X:0>16}\n", .{ctx.rax});
        try writer.print("RBX    : 0x{X:0>16}\n", .{ctx.rbx});
        try writer.print("RCX    : 0x{X:0>16}\n", .{ctx.rcx});
        try writer.print("RDX    : 0x{X:0>16}\n", .{ctx.rdx});
        try writer.print("RSI    : 0x{X:0>16}\n", .{ctx.rsi});
        try writer.print("RDI    : 0x{X:0>16}\n", .{ctx.rdi});
        try writer.print("RSP    : 0x{X:0>16}\n", .{ctx.rsp});
        try writer.print("RBP    : 0x{X:0>16}\n", .{ctx.rbp});
        try writer.print("R8     : 0x{X:0>16}\n", .{ctx.r8});
        try writer.print("R9     : 0x{X:0>16}\n", .{ctx.r9});
        try writer.print("R10    : 0x{X:0>16}\n", .{ctx.r10});
        try writer.print("R11    : 0x{X:0>16}\n", .{ctx.r11});
        try writer.print("R12    : 0x{X:0>16}\n", .{ctx.r12});
        try writer.print("R13    : 0x{X:0>16}\n", .{ctx.r13});
        try writer.print("R14    : 0x{X:0>16}\n", .{ctx.r14});
        try writer.print("R15    : 0x{X:0>16}\n", .{ctx.r15});
        try writer.print("CS     : 0x{X:0>4}", .{ctx.cs});
    }
};
