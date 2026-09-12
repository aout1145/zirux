const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;
const acpi = root.drivers.acpi;
const allocator = root.mem.general_allocator;

pub const idt = @import("idt.zig");
pub const isr = @import("isr.zig");
pub const apic = @import("apic.zig");
pub const ipi = @import("ipi.zig");

pub fn init() !void {
    asm volatile ("cli");

    // Block interrupt vector 0~31.
    var cr8 = arch.@"asm".readCtrlRegister(arch.@"asm".registers.Cr8, "cr8");
    cr8.tpr = 1;
    arch.@"asm".writeCtrlRegister("cr8", cr8);

    idt.init();
    try isr.init(allocator);
    asm volatile ("sti");

    try apic.init();
}

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
