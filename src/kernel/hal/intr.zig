const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

pub const IrqNumber = u32;
pub inline fn getIrq() IrqNumber {
    @panic("TODO");
}
/// Disable interrupt and save flags
pub inline fn irqSave() u8 {
    return arch.intr.irqSave();
}
/// Ensable interrupt and restore flags
pub inline fn irqRestore(flag: u8) void {
    arch.intr.irqRestore(flag);
}
