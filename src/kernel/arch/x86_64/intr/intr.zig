const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;
const acpi = root.drivers.acpi;

pub const idt = @import("idt.zig");
pub const isr = @import("isr.zig");
pub const apic = @import("apic.zig");
pub const apic_timer = @import("apic_timer.zig");

pub fn init(gpa: std.mem.Allocator, xsdt: *acpi.XSDT) !void {
    idt.init();
    try isr.init(gpa);
    asm volatile ("sti");
    try apic.init(xsdt);
    try apic_timer.init();
}

var preempt_count: u32 linksection(arch.cpu.per_cpu.section) = 1;

pub inline fn irqSave() u8 {
    const rflags = arch.@"asm".readRflags();
    asm volatile ("cli");
    return @intFromBool(rflags.@"if");
}
pub inline fn irqRestore(flag: u8) void {
    var rflags = arch.@"asm".readRflags();
    rflags.@"if" = (flag == 1);
    arch.@"asm".writeRflags(rflags);
}

pub inline fn getPreemptCount() u32 {
    return arch.cpu.per_cpu.read(u32, &preempt_count);
}
pub inline fn preemptDisable() void {
    arch.cpu.per_cpu.add(u32, &preempt_count, 1);
}
pub inline fn preemptEnable() void {
    assert(getPreemptCount() != 0);
    arch.cpu.per_cpu.sub(u32, &preempt_count, 1);
}
