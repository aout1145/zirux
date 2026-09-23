const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;
const hal = root.hal;
const log = root.debug.log;

pub fn init() !void {
    if (acpi.xsdt.?.find(acpi.tables.HPET, "HPET")) |hpet_table| {
        log.info(@src(), "Found HPET device.", .{});

        hpet_base = try acpi.utils.mapAddress(hpet_table.address, 1024);
        hpet = .{ .vtable = &hpet_vtable };
    }
}

var hpet_base: ?hal.io.IoRegion = null;
const HpetRegisters = enum(usize) {
    /// General Capabilities and ID Register
    gcir = 0x000,
    /// General Configuration Register
    gcr = 0x010,
    /// Main Counter Value Register
    mcvr = 0x0F0,
};
const GeneralCapabilitiesAndIdRegister = packed struct(u64) {
    /// Indicates which revision of the function is implemented; must not be 0.
    rev_id: u8,
    /// The amount of timers - 1.
    num_tim_cap: u5,
    /// If this bit is 1, HPET main counter is capable of operating in 64 bit mode.
    count_size_cap: bool,
    _reserved0: u1,
    /// If this bit is 1, HPET is capable of using "legacy replacement" mapping.
    leg_rt_cap: bool,
    /// This field should be interpreted similarly to PCI's vendor ID.
    vendor_id: u16,
    /// Main counter tick period in femtoseconds (10^-15 seconds). Must not be zero, must be less or equal to 0x05F5E100, or 100 nanoseconds.
    counter_clk_period: u32,
};
const GeneralConfigurationRegister = packed struct(u64) {
    /// Overall enable
    enable_cnf: bool,
    /// Legacy replacement mapping enable
    leg_rt_cnf: bool,
    _reserved: u62,
};

const hpet_vtable: hal.time.ClockSource.VTable = .{
    .getStatus = getStatus,
    .setStatus = setStatus,
    .getHz = getHz,
    .getCount = getCount,
};
fn getStatus(_: *const hal.time.ClockSource) hal.time.ClockSource.Status {
    const gcr: GeneralConfigurationRegister = @bitCast(hpet_base.?.read64(@intFromEnum(HpetRegisters.gcr)));
    return if (gcr.enable_cnf) .running else .stopped;
}
fn setStatus(_: *hal.time.ClockSource, status: hal.time.ClockSource.Status) void {
    var gcr: GeneralConfigurationRegister = @bitCast(hpet_base.?.read64(@intFromEnum(HpetRegisters.gcr)));
    gcr.enable_cnf = (status == .running);
    hpet_base.?.write64(@intFromEnum(HpetRegisters.gcr), @bitCast(gcr));
}
fn getHz(_: *const hal.time.ClockSource) u64 {
    const gcir: GeneralCapabilitiesAndIdRegister = @bitCast(hpet_base.?.read64(@intFromEnum(HpetRegisters.gcir)));
    return std.math.pow(u64, 10, 15) / gcir.counter_clk_period;
}
fn getCount(_: *const hal.time.ClockSource) u64 {
    return hpet_base.?.read64(@intFromEnum(HpetRegisters.mcvr));
}
pub var hpet: ?hal.time.ClockSource = null;
