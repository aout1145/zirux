const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;

const idt = @import("idt.zig");
const isr = @import("isr.zig");

pub fn init(gpa: std.mem.Allocator) !void {
    _ = gpa;
    idt.init();
    isr.init();
    asm volatile ("sti");
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
