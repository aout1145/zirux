const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const log = root.debug.log;

const GateDescriptor = packed struct(u128) {
    /// Lower 16 bits of the offset to the ISR.
    offset_low: u16,
    /// Segment Selector that must point to a valid code segment in the GDT.
    segment_selector: u16,
    /// Interrupt Stack Table.
    ist: u3,
    /// Reserved.
    _reserved1: u5 = 0,
    /// Gate Type.
    gate_type: GateType,
    /// Reserved.
    _reserved2: u1 = 0,
    /// Descriptor Privilege Level is the required CPL to call the ISR via the INT inst.
    /// Hardware interrupts ignore this field.
    dpl: u2,
    /// Present flag.
    present: bool,
    /// Middle 48 bits of the offset to the ISR.
    offset_high: u48,
    /// Reserved.
    _reserved3: u32 = 0,
};
const GateType = enum(u4) {
    invalid = 0b0000,
    interrupt64 = 0b1110,
    trap64 = 0b1111,
};

var idt: [256]GateDescriptor align(arch.mem.page.page_size) linksection(arch.cpu.per_cpu.section) = .{
    std.mem.zeroes(GateDescriptor),
} ** 256;

pub fn setGate(
    index: usize,
    gate_type: GateType,
    offset: u64,
    use_isr: bool,
) void {
    const local_gate = arch.cpu.per_cpu.ptr(GateDescriptor, &idt[index]);
    local_gate.* = .{
        .present = true,
        .offset_low = @truncate(offset),
        .segment_selector = @bitCast(arch.cpu.gdt.kernel_cs_selector),
        .gate_type = gate_type,
        .offset_high = @truncate(offset >> 16),
        .dpl = 0,
        .ist = if (use_isr) 1 else 0,
    };
}

const IdtRegister = packed struct {
    limit: u16,
    base: u64,
};
var idtr: IdtRegister linksection(arch.cpu.per_cpu.section) = .{
    .limit = @sizeOf(@TypeOf(idt)) - 1,
    .base = undefined,
};
fn lidt(val: u64) void {
    asm volatile (
        \\lidt (%[idtr])
        :
        : [idtr] "r" (val),
    );
}

pub fn init() void {
    const local_idtr = arch.cpu.per_cpu.ptr(IdtRegister, &idtr);
    local_idtr.base = @intFromPtr(arch.cpu.per_cpu.ptr(@TypeOf(idt), &idt));
    lidt(@intFromPtr(local_idtr));
}
