const root = @import("root");
const arch = root.arch.x86_64;

pub const gdt = @import("gdt.zig");
pub const per_cpu = @import("per_cpu.zig");
pub const context = @import("context.zig");
pub const smp = @import("smp.zig");

pub const cache_line: usize = 64;

pub fn init() void {
    var cr0 = arch.@"asm".readCtrlRegister(arch.@"asm".registers.Cr0, "cr0");
    cr0.mp = true;
    cr0.em = false;
    cr0.et = true;
    cr0.ne = true;
    cr0.wp = true;
    cr0.am = true;
    arch.@"asm".writeCtrlRegister("cr0", cr0);
}

pub inline fn endlessHalt() void {
    while (true) {
        asm volatile ("hlt");
    }
}
