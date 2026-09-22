const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const log = root.debug.log;
const assert = std.debug.assert;

const idt = arch.intr.idt;
const apic = arch.intr.apic;

pub const Vector = enum(u8) {
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
    lapic_timer = 32,
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

    pub inline fn isUseIst(vector: Vector) bool {
        return switch (vector) {
            .double_fault,
            .non_maskable_interrupt,
            .machine_check,
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

const Isr = *const fn () callconv(.naked) void;
export var intr_sp: u64 linksection(arch.cpu.per_cpu.section) = 0;
pub fn generateIsr(comptime vector: Vector) Isr {
    return struct {
        fn handler() callconv(.naked) void {
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
                \\
                :
                : [vector] "n" (vector),
            );
            // Save the general-purpose registers.
            asm volatile (
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
            );
            // Push the context and call the handler.
            if (vector.isUseIst()) {
                // Use IST: no need to switch intr_stack (hardware has done it)
                asm volatile (
                    \\movq %%rsp, %%rdi
                    // Align stack to 16 bytes.
                    \\pushq %%rsp
                    \\pushq (%%rsp)
                    \\andq $-0x10, %%rsp
                    // Call the dispatcher.
                    \\call intrZigEntry
                    // Restore the stack.
                    \\movq 8(%%rsp), %%rsp
                );
            } else if (vector.type() == .interrupt) {
                // Hard interrupt: switch to intr_stack (mannually)
                asm volatile (
                    \\movq %%rsp, %%rdi
                    // Switch to new stack.
                    \\movq %%gs:intr_sp, %%rsp
                    \\pushq %%rdi
                    // Call the dispatcher.
                    \\call intrZigEntry
                    \\popq %%rsp
                );
            } else {
                // Exception: use the kernel stack of process
                // More: enable interrupt
                asm volatile (
                    \\movq %%rsp, %%rdi
                    // Align stack to 16 bytes.
                    \\pushq %%rsp
                    \\pushq (%%rsp)
                    \\andq $-0x10, %%rsp
                    // Call the dispatcher.
                    \\sti
                    \\call intrZigEntry
                    \\cli
                    // Restore the stack.
                    \\movq 8(%%rsp), %%rsp
                );
            }
            // Try reschedule
            if (!vector.isUseIst()) {
                asm volatile (
                    \\
                    // Align stack to 16 bytes.
                    \\pushq %%rsp
                    \\pushq (%%rsp)
                    \\andq $-0x10, %%rsp
                    // Call reschedule
                    \\call reschedule
                    // Restore the stack.
                    \\movq 8(%%rsp), %%rsp
                );
            }
            asm volatile (
                \\jmp isrExit
            );
        }
    }.handler;
}
export fn isrExit() callconv(.naked) void {
    // Remove general-purpose registers, error code, and vector from the stack
    asm volatile (
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
    );
    // Swap GS if to userspace, and return
    asm volatile (
        \\cmpq $0x08, 0x8(%rsp)
        \\je 1f
        \\swapgs
        \\1:
        \\iretq
    );
}
export fn intrZigEntry(ctx: *arch.cpu.context.Context) callconv(.c) void {
    // When vector >= 128, pushq will expanded it into 0xFFFFFFFFFFFFFF__,
    // So we &= 0xFF to solve it.
    const vector = Vector.fromNumber(ctx.vector & 0xFF);
    if (vector.isUseIst() or vector.type() == .interrupt) root.sched.preemptDisable();
    defer if (vector.isUseIst() or vector.type() == .interrupt) root.sched.preemptEnable();

    const handler = arch.cpu.per_cpu.read(Handler, &handlers[vector.number()]);
    handler(ctx);
}

const Handler = *const fn (*arch.cpu.context.Context) void;
var handlers: [256]Handler linksection(arch.cpu.per_cpu.section) = [_]Handler{unhandledHandler} ** 256;
fn unhandledHandler(ctx: *arch.cpu.context.Context) void {
    asm volatile ("cli");
    switch (Vector.fromNumber(ctx.vector).type()) {
        .abort, .fault, .reserved => {
            arch.debug.setPanicFlag();
            log.err(@src(), "============ Oops! ===================", .{});
            log.err(@src(), "Unhandled exception: {s} ({})", .{ Vector.fromNumber(ctx.vector).name(), ctx.vector });
            log.err(@src(), "Error Code: 0x{X}", .{ctx.error_code});
            if (Vector.fromNumber(ctx.vector) == .page_fault) {
                log.err(@src(), "CR2    : 0x{X:0>16}", .{arch.@"asm".readRegister("cr2")});
            }
            log.err(@src(), "{f}", .{ctx});
            @panic("Unhandled exception");
        },
        .trap => {
            log.debug(@src(), "Unhandled trap: {s} ({})", .{ Vector.fromNumber(ctx.vector).name(), ctx.vector });
            // log.debug(@src(), "{f}", .{ctx});
        },
        .interrupt => {
            // Check if kernel panicked
            if (arch.debug.panic_flag.load(.acquire)) {
                arch.cpu.endlessHalt();
            }
            log.debug(@src(), "Unhandled interrupt: {}", .{ctx.vector});
            apic.sendEoi();
        },
    }
}
pub fn setHandler(vector: u8, handler: Handler) void {
    const flag = arch.intr.irqSave();
    defer arch.intr.irqRestore(flag);

    const local_handers = arch.cpu.per_cpu.ptr([256]Handler, &handlers);
    assert(local_handers[vector] == unhandledHandler);
    local_handers[vector] = handler;
}

pub fn init(gpa: std.mem.Allocator) !void {
    const intr_stack = try gpa.alignedAlloc(
        u8,
        .fromByteUnits(arch.mem.page.page_size),
        4 * arch.mem.page.page_size,
    );
    const local_intr_sp = @intFromPtr(intr_stack.ptr) + intr_stack.len - 8;
    arch.cpu.per_cpu.write(u64, &intr_sp, local_intr_sp);
    const local_tss = arch.cpu.per_cpu.ptr(arch.cpu.gdt.TaskStateSegment, &arch.cpu.gdt.tss);
    local_tss.ist1 = local_intr_sp;
    inline for (0..256) |i| {
        const vector: Vector = @enumFromInt(i);
        idt.setGate(
            i,
            .interrupt64,
            @intFromPtr(generateIsr(vector)),
            vector.isUseIst(),
        );
    }
}
