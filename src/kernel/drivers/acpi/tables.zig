const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;

/// Multiple APIC Description Table
pub const MADT = extern struct {
    header: acpi.SDTH align(1),
    lapic_address: u32 align(1),
    flags: Flags align(1),

    pub const Flags = packed struct(u32) {
        /// true = Dual 8259 Legacy PICs Installed
        pcat_compat: bool,
        _reserved: u31,
    };

    // TODO: others
};
