const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;
const acpi = root.drivers.acpi;
const hal = root.hal;
const mem = root.mem;

pub fn init() !void {
    const madt = acpi.xsdt.?.find(acpi.tables.MADT, "APIC") orelse return error.NotFound;
    const io_region = try mem.vmap.ioMap(madt.lapic_addr, hal.page.page_size, .uncacheable);
    const local_lapic = arch.cpu.per_cpu.ptr(hal.io.IoRegion, &lapic_base);
    local_lapic.* = io_region;

    var svr: SpuriousVectorRegister = @bitCast(lapicRead(.svr));
    svr.spurious_vector = 0xFF;
    svr.apic_enabled = true;
    lapicWrite(.svr, @bitCast(svr));
}

pub fn sendEoi() void {
    lapicWrite(.eoi, 0);
}

var lapic_base: hal.io.IoRegion linksection(arch.cpu.per_cpu.section) = undefined;
pub const LocalApicRegisters = enum(u32) {
    /// LAPIC ID Register
    id = 0x020,
    /// LAPIC Version Register
    version = 0x030,
    /// Spurious Vector Register
    svr = 0x0F0,
    /// End of Interrupt
    eoi = 0x0B0,
    /// LVT Timer Register
    lvt_timer = 0x320,
    /// Initial Count Register (for Timer)
    initial_cnt = 0x380,
    /// Current Count Register (for Timer)
    current_cnt = 0x390,
    /// Divide Configuration Register (for Timer)
    divide_conf = 0x3E0,
    /// Interrupt Command Register
    icr_low = 0x300,
    icr_high = 0x310,
    // TODO: Add more
};
pub inline fn lapicRead(reg: LocalApicRegisters) u32 {
    const local_lapic = arch.cpu.per_cpu.ptr(hal.io.IoRegion, &lapic_base);
    return local_lapic.read32(@intFromEnum(reg));
}
pub inline fn lapicWrite(reg: LocalApicRegisters, value: u32) void {
    const local_lapic = arch.cpu.per_cpu.ptr(hal.io.IoRegion, &lapic_base);
    local_lapic.write32(@intFromEnum(reg), value);
}

const SpuriousVectorRegister = packed struct(u32) {
    spurious_vector: u8,
    apic_enabled: bool,
    _reserved: u23,
};
