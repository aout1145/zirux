const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const log = root.debug.log;

const idt = @import("idt.zig");

const Vector = enum(u8) {
    // Exceptions
    division_error = 0,
    debug = 1,
    non_maskable_interrupt = 2,
    breakpoint = 3,
    overflow = 4,
    bound_range_exceeded = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    coprocessor_segment_overrun = 9,
    invalid_tss = 10,
    segment_not_present = 11,
    stack_segment_fault = 12,
    general_protection_fault = 13,
    page_fault = 14,
    reserved_exception_15 = 15,
    x87_fpu_error = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_floating_point_exception = 19,
    virtualization_exception = 20,
    control_protection_exception = 21,
    reserved_exception_22 = 22,
    reserved_exception_23 = 23,
    reserved_exception_24 = 24,
    reserved_exception_25 = 25,
    reserved_exception_26 = 26,
    reserved_exception_27 = 27,
    reserved_exception_28 = 28,
    reserved_exception_29 = 29,
    reserved_exception_30 = 30,
    reserved_exception_31 = 31,
    // Interrupts
    timer = 32,
    _,

    pub const Type = enum {
        reserved,
        fault,
        trap,
        abort,
        interrupt,
    };
    pub inline fn @"type"(vector: Vector) Type {
        return switch (vector) {
            .division_error => .fault,
            .debug => .trap,
            .non_maskable_interrupt => .interrupt,
            .breakpoint => .trap,
            .overflow => .trap,
            .bound_range_exceeded => .fault,
            .invalid_opcode => .fault,
            .device_not_available => .fault,
            .double_fault => .abort,
            .coprocessor_segment_overrun => .fault,
            .invalid_tss => .fault,
            .segment_not_present => .fault,
            .stack_segment_fault => .fault,
            .general_protection_fault => .fault,
            .page_fault => .fault,
            .x87_fpu_error => .fault,
            .alignment_check => .fault,
            .machine_check => .abort,
            .simd_floating_point_exception => .fault,
            .virtualization_exception => .fault,
            .control_protection_exception => .fault,
            .reserved_exception_15,
            .reserved_exception_22,
            .reserved_exception_23,
            .reserved_exception_24,
            .reserved_exception_25,
            .reserved_exception_26,
            .reserved_exception_27,
            .reserved_exception_28,
            .reserved_exception_29,
            .reserved_exception_30,
            .reserved_exception_31,
            => .reserved,
            else => .interrupt,
        };
    }

    pub inline fn name(vector: Vector) []const u8 {
        return switch (vector) {
            .division_error => "#DE: Divide Error",
            .debug => "#DB: Debug Exception",
            .non_maskable_interrupt => "NMI: NMI Interrupt",
            .breakpoint => "#BP: Breakpoint",
            .overflow => "#OF: Overflow",
            .bound_range_exceeded => "#BR: BOUND Range Exceeded",
            .invalid_opcode => "#UD: Invalid Opcode",
            .device_not_available => "#NM: Device Not Available",
            .double_fault => "#DF: Double Fault",
            .coprocessor_segment_overrun => "Coprocessor Segment Overrun",
            .invalid_tss => "#TS: Invalid TSS",
            .segment_not_present => "#NP: Segment Not Present",
            .stack_segment_fault => "#SS: Stack-Segment Fault",
            .general_protection_fault => "#GP: General Protection",
            .page_fault => "#PF: Page Fault",
            .x87_fpu_error => "#MF: x87 FPU Floating-Point Error",
            .alignment_check => "#AC: Alignment Check",
            .machine_check => "#MC: Machine Check",
            .simd_floating_point_exception => "#XM: SIMD Floating-Point Exception",
            .virtualization_exception => "#VE: Virtualization Exception",
            .control_protection_exception => "#CP: Control Protection Exception",
            .reserved_exception_15,
            .reserved_exception_22,
            .reserved_exception_23,
            .reserved_exception_24,
            .reserved_exception_25,
            .reserved_exception_26,
            .reserved_exception_27,
            .reserved_exception_28,
            .reserved_exception_29,
            .reserved_exception_30,
            .reserved_exception_31,
            => "Unknown Exception",
            else => "External Interrupt",
        };
    }

    pub inline fn hasErrorCode(vector: Vector) bool {
        return switch (vector) {
            .double_fault,
            .invalid_tss,
            .segment_not_present,
            .stack_segment_fault,
            .general_protection_fault,
            .page_fault,
            .alignment_check,
            .control_protection_exception,
            => true,
            else => false,
        };
    }

    pub inline fn number(vector: Vector) u8 {
        return @intFromEnum(vector);
    }
    pub inline fn fromNumber(int: u64) Vector {
        return @enumFromInt(int);
    }
};

pub const Isr = *const fn () callconv(.naked) void;
pub fn generateIsr(comptime vector: Vector) Isr {
    return struct {
        fn handler() callconv(.naked) void {
            // Clear the interrupt flag.
            asm volatile (
                \\cli
            );
            // If the interrupt does not provide an error code, push a dummy one.
            if (!vector.hasErrorCode()) {
                asm volatile (
                    \\pushq $0
                );
            }
            // Swap GS if from userspace.
            asm volatile (
                \\cmpq $0x08, 0x10(%rsp)
                \\je 1f
                \\swapgs
                \\1:
            );
            // Push the vector.
            asm volatile (
                \\pushq %[vector]
                :
                : [vector] "n" (vector),
            );
            // Jump to the common ISR.
            asm volatile (
                \\jmp isrCommon
            );
        }
    }.handler;
}
export fn isrCommon() callconv(.naked) void {
    asm volatile (
        \\
        // Save the general-purpose registers.
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

        // Push the context and call the handler.
        \\pushq %%rsp
        \\popq %%rdi
        // Align stack to 16 bytes.
        \\pushq %%rsp
        \\pushq (%%rsp)
        \\andq $-0x10, %%rsp
        // Call the dispatcher.
        \\call intrZigEntry
        // Restore the stack.
        \\movq 8(%%rsp), %%rsp

        // Remove general-purpose registers, error code, and vector from the stack
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
        \\popq %%rax
        \\
        \\addq $0x10, %%rsp

        // Swap GS if to userspace, and return
        \\cmpq $0x08, 0x8(%rsp)
        \\je 1f
        \\swapgs
        \\1:
        \\iretq
    );
}
export fn intrZigEntry(ctx: *arch.cpu.context.Context) callconv(.c) void {
    const handler = arch.cpu.per_cpu.read(Handler, &handlers[ctx.vector]);
    handler(ctx);
}

const Handler = *const fn (*arch.cpu.context.Context) void;
var handlers: [256]Handler linksection(arch.cpu.per_cpu.section) = [_]Handler{unhandledHandler} ** 256;
fn unhandledHandler(ctx: *arch.cpu.context.Context) void {
    log.err(@src(), "============ Oops! ===================", .{});
    log.err(@src(), "Unhandled interrupt: {s} ({})", .{ Vector.fromNumber(ctx.vector).name(), ctx.vector });
    log.err(@src(), "Error Code: 0x{X}", .{ctx.error_code});
    if (Vector.fromNumber(ctx.vector) == .page_fault) {
        log.err(@src(), "CR2    : 0x{X:0>16}", .{arch.@"asm".readRegister("cr2")});
    }
    log.err(@src(), "{f}", .{ctx});

    while (true) {
        arch.@"asm".halt();
    }
}

pub fn init() void {
    inline for (0..256) |i| {
        const vector: Vector = @enumFromInt(i);
        idt.setGate(
            i,
            .interrupt64,
            @intFromPtr(generateIsr(vector)),
            switch (vector) {
                .double_fault,
                .non_maskable_interrupt,
                .machine_check,
                => true,
                else => false,
            },
        );
    }
}
