const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;
const assert = std.debug.assert;

/// Multiple APIC Description Table
/// See also: https://wiki.osdev.org/MADT
pub const MADT = extern struct {
    header: acpi.SDTH align(1),
    lapic_addr: u32 align(1),
    flags: Flags align(1),
    pub const Flags = packed struct(u32) {
        /// true = Dual 8259 Legacy PICs Installed
        pcat_compat: bool,
        _reserved: u31,
    };

    pub const EntryType = enum(u8) {
        /// Processor Local APIC
        lapic = 0,
        /// I/O APIC
        ioapic = 1,
        /// I/O APIC Interrupt Source Override
        ioapic_intr_source_override = 2,
        /// I/O APIC Non-maskable interrupt source
        ioapic_nmi_source = 3,
        /// Local APIC Non-maskable interrupts
        lapic_nmi = 4,
        /// Local APIC Address Override
        lapic_addr_override = 5,
        /// Processor Local x2APIC
        lx2apic = 9,
    };
    pub const EntryHeader = extern struct {
        type: EntryType align(1),
        length: u8 align(1),
        pub inline fn as(self: *const EntryHeader, @"type": EntryType) *const Entry(@"type") {
            assert(self.type == @"type");
            return @ptrCast(@alignCast(self));
        }
    };
    pub fn Entry(@"type": EntryType) type {
        return switch (@"type") {
            .lapic => extern struct {
                header: EntryHeader align(1),
                processor_id: u8 align(1),
                apic_id: u8 align(1),
                flags: Entry0Flags align(1),
                pub const Entry0Flags = packed struct(u32) {
                    processor_enabled: bool,
                    online_capable: bool,
                    _reserved: u30,
                };
            },
            else => unreachable,
        };
    }
    pub fn iter(madt: *const MADT) Iterator {
        return .{
            .start = @intFromPtr(madt) + @sizeOf(MADT),
            .end = @intFromPtr(madt) + madt.header.length,
        };
    }
    pub const Iterator = struct {
        start: usize,
        end: usize,
        pub fn next(self: *Iterator) ?*const EntryHeader {
            if (self.start >= self.end) {
                return null;
            } else {
                const header: *const EntryHeader = @ptrFromInt(self.start);
                self.start += header.length;
                return header;
            }
        }
    };
};
comptime {
    assert(@alignOf(MADT) == 1);
    assert(@alignOf(MADT.EntryHeader) == 1);
    assert(@alignOf(MADT.Entry(.lapic)) == 1);
}
