const std = @import("std");
const root = @import("root");
const hal = root.hal;
const arch = root.arch.x86_64;

pub fn init() !void {
    const @"asm" = arch.@"asm";
    const registers = @"asm".registers;

    var efer = @"asm".readCtrlMsr(registers.Efer, registers.Efer.msr);
    efer.sce = true;
    @"asm".writeCtrlMsr(registers.Efer.msr, efer);

    var star = @"asm".readCtrlMsr(registers.Star, registers.Star.msr);
    star.kernel_segments = @bitCast(arch.cpu.gdt.kernel_cs_selector);
    star.user_segments = @as(u16, @bitCast(arch.cpu.gdt.user_ds_selector)) - 8;
    @"asm".writeCtrlMsr(registers.Star.msr, star);

    var lstar = @"asm".readCtrlMsr(registers.Lstar, registers.Lstar.msr);
    lstar.rip = @intFromPtr(&syscallEntry);
    @"asm".writeCtrlMsr(registers.Lstar.msr, lstar);

    var fmask = @"asm".readCtrlMsr(registers.Fmask, registers.Fmask.msr);
    fmask.mask = std.mem.zeroInit(registers.Rflags, .{
        .cf = true,
        .pf = true,
        .af = true,
        .zf = true,
        .sf = true,
        .tf = true,
        .@"if" = true,
        .df = true,
        .of = true,
        .iopl = 0b11,
        .nt = true,
        .rf = true,
        .ac = true,
        .id = true,
    });
    @"asm".writeCtrlMsr(registers.Fmask.msr, fmask);
}

var dispatcher: ?hal.syscall.Dispatcher = null;
pub inline fn setDispatcher(arg_dispatcher: hal.syscall.Dispatcher) void {
    dispatcher = arg_dispatcher;
}

pub export var kernel_rsp: u64 linksection(arch.cpu.per_cpu.section) = undefined;
export var user_rsp: u64 linksection(arch.cpu.per_cpu.section) = undefined;
fn syscallEntry() callconv(.naked) void {
    asm volatile (
        \\
        // Switch to kernel stack
        \\swapgs
        \\movq %%rsp, %%gs:user_rsp
        \\movq %%gs:kernel_rsp, %%rsp
        \\pushq %%gs:user_rsp
        // Save context
        \\pushq %%rcx
        \\pushq %%r11
        \\
        \\pushq %%rbx
        \\pushq %%rbp
        \\pushq %%r12
        \\pushq %%r13
        \\pushq %%r14
        \\pushq %%r15
        // Push argument registers
        \\pushq %%r9
        \\pushq %%r8
        \\pushq %%r10
        \\pushq %%rdx
        \\pushq %%rsi
        \\pushq %%rdi
        \\pushq %%rax
        // Call syscallDispatch
        \\movq %%rsp, %%rdi
        \\sti
        \\call syscallDispatch
        \\cli
        // Set return value
        \\popq %%rax
        \\addq $(6*8), %%rsp
        // Restore context
        \\popq %%r15
        \\popq %%r14
        \\popq %%r13
        \\popq %%r12
        \\popq %%rbp
        \\popq %%rbx
        \\
        \\popq %%r11
        \\popq %%rcx
        // Switch to user stack and return
        \\popq %%rsp
        \\swapgs
        \\sysretq
    );
}
const Registers = extern struct {
    rax: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    r10: u64,
    r8: u64,
    r9: u64,
};
export fn syscallDispatch(registers: *Registers) callconv(.c) void {
    if (dispatcher) |dispatchFunc| {
        registers.rax = dispatchFunc(registers.rax, @ptrCast(&registers.rdi));
    }
}
