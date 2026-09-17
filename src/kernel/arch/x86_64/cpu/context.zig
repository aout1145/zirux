const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const arch = root.arch.x86_64;
const assert = std.debug.assert;

pub const Context = extern struct {
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

export fn reschedule() callconv(.c) void {
    if (root.sched.isNeedReschedule() and root.sched.getPreemptCount() == 0) {
        root.sched.clearRescheduleFlag();
        root.sched.thread.schedule();
    }
}

const SwitchContext = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    rbp: u64,
    rbx: u64,
    gs_base: u64,
    fs_base: u64,
    rip: u64,
};

extern fn isrExit() callconv(.naked) void;
pub fn init(stack: []u8, entry: u64, userspace: bool) u64 {
    const stack_base = @intFromPtr(stack.ptr) + stack.len;

    const sw_ctx: *SwitchContext = @ptrFromInt(stack_base - @sizeOf(Context) - @sizeOf(SwitchContext));
    sw_ctx.* = std.mem.zeroInit(SwitchContext, .{
        .rip = @intFromPtr(&isrExit),
    });

    const ctx: *Context = @ptrFromInt(stack_base - @sizeOf(Context));
    const cs: u16 = @bitCast(if (userspace) arch.cpu.gdt.user_cs_selector else arch.cpu.gdt.kernel_cs_selector);
    const ss: u16 = @bitCast(if (userspace) arch.cpu.gdt.user_ds_selector else arch.cpu.gdt.kernel_ds_selector);
    ctx.* = std.mem.zeroInit(Context, .{
        .rip = entry,
        .rflags = 0x202, // IF
        .cs = cs,
        .ss = ss,
    });
    return @intFromPtr(sw_ctx);
}

pub inline fn switchTo(save_sp: *u64, next_stack: []u8, next_sp: u64) void {
    assert(root.sched.getPreemptCount() == 0);
    // Update tss.rsp0
    const tss = arch.cpu.per_cpu.ptr(arch.cpu.gdt.TaskStateSegment, &arch.cpu.gdt.tss);
    // log.debug(@src(), "{} {}", .{ @intFromPtr(next_stack.ptr), next_stack.len });
    tss.rsp0 = @intFromPtr(next_stack.ptr) + next_stack.len;
    // Update syscall.kernel_rsp
    arch.cpu.per_cpu.write(u64, &arch.syscall.kernel_rsp, @intFromPtr(next_stack.ptr) + next_stack.len);
    // Perform context switch
    cSwitchTo(save_sp, next_sp);
}
fn cSwitchTo(save_sp: *u64, next_sp: u64) callconv(.c) void {
    asm volatile (
        \\call doSwitchTo
        :
        : [save_sp] "{rdi}" (save_sp),
          [next_sp] "{rsi}" (next_sp),
        : .{
          .memory = true,
          .rbx = true,
          .rbp = true,
          .r12 = true,
          .r13 = true,
          .r14 = true,
          .r15 = true,
          .rax = true,
          .rcx = true,
          .rdx = true,
          .cc = true,
        });
}
export fn doSwitchTo() callconv(.naked) void {
    asm volatile (
        \\
        // Save FS.Base/KernelGS.Base
        \\movl $0xC0000100, %%ecx
        \\rdmsr
        \\shlq $32, %%rdx
        \\orq  %%rdx, %%rax
        \\pushq %%rax
        \\
        \\movl $0xC0000102, %%ecx
        \\rdmsr
        \\shlq $32, %%rdx
        \\orq  %%rdx, %%rax
        \\pushq %%rax
        // Save registers
        \\pushq %%rbx
        \\pushq %%rbp
        \\pushq %%r12
        \\pushq %%r13
        \\pushq %%r14
        \\pushq %%r15
        // Switch rsp
        \\movq %%rsp, (%%rdi)
        \\movq %%rsi, %%rsp
        // Restore registers
        \\popq %%r15
        \\popq %%r14
        \\popq %%r13
        \\popq %%r12
        \\popq %%rbp
        \\popq %%rbx
        // Restore FS.Base/KernelGS.Base
        \\popq %%rax
        \\movq %%rax, %%rdx
        \\shrq $32, %%rdx
        \\movl $0xC0000102, %%ecx
        \\wrmsr
        \\
        \\popq %%rax
        \\movq %%rax, %%rdx
        \\shrq $32, %%rdx
        \\movl $0xC0000100, %%ecx
        \\wrmsr
        // Return
        \\retq
    );
}
