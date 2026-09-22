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
        // Save context
        // rip in %rcx, rflags in %r11
        \\pushq %[user_ss]
        \\pushq %%gs:user_rsp
        \\pushq %%r11
        \\pushq %[user_cs]
        \\pushq %%rcx
        \\pushq $0
        \\pushq $0xFF
        \\
        \\pushq %%rax
        \\pushq %%rbx
        \\pushq %%rcx
        \\pushq %%rdx
        \\pushq %%rsi
        \\pushq %%rdi
        \\pushq %%rbp
        \\pushq %%r8
        \\pushq %%r9
        \\pushq %%r10
        \\pushq %%r11
        \\pushq %%r12
        \\pushq %%r13
        \\pushq %%r14
        \\pushq %%r15
        // Call syscallDispatch
        \\movq %%rsp, %%rdi
        \\sti
        \\call syscallDispatch
        \\cli
        // Try reschedule
        \\call reschedule
        // Restore context
        \\popq %%r15
        \\popq %%r14
        \\popq %%r13
        \\popq %%r12
        \\popq %%r11
        \\popq %%r10
        \\popq %%r9
        \\popq %%r8
        \\popq %%rbp
        \\popq %%rdi
        \\popq %%rsi
        \\popq %%rdx
        \\popq %%rcx
        \\popq %%rbx
        \\addq $0x08, %%rsp
        \\
        \\addq $0x10, %%rsp
        \\popq %%rcx
        \\addq $0x08, %%rsp
        \\popq %%r11
        \\popq %%rsp
        // Return
        \\swapgs
        \\sysretq
        :
        : [user_ss] "n" (arch.cpu.gdt.user_ds_selector),
          [user_cs] "n" (arch.cpu.gdt.user_cs_selector),
    );
}
export fn syscallDispatch(registers: *arch.cpu.context.Context) callconv(.c) void {
    if (dispatcher) |dispatchFunc| {
        registers.rax = dispatchFunc(registers.rax, &.{
            registers.rdi,
            registers.rsi,
            registers.rdx,
            registers.r10,
            registers.r8,
            registers.r9,
        });
    }
}
