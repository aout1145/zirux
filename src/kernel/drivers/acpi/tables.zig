const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;
const assert = std.debug.assert;

/// Extended Root System Description Pointer
pub const XSDP = extern struct {
    signature: [8]u8 align(1),
    checksum: u8 align(1),
    oemid: [6]u8 align(1),
    revision: u8 align(1),
    _rsdt_address: u32 align(1),
    length: u32 align(1),
    xsdt_address: u64 align(1),
    extended_checksum: u8 align(1),
    _reserved: [3]u8 align(1),

    pub const ParseError = error{
        InvalidSignature,
        InvalidVersion,
        InvalidChecksum,
        InvalidExtendedChecksum,
    };
    pub fn parse(xsdp_base: usize) !*XSDP {
        const xsdp: *XSDP = @ptrFromInt(root.hal.page.direct_map_base + xsdp_base);

        if (!std.mem.eql(u8, &xsdp.signature, "RSD PTR "))
            return ParseError.InvalidSignature;
        if (xsdp.revision != 2)
            return ParseError.InvalidVersion;

        const bytes: [*]const u8 = @ptrCast(xsdp);
        const bytes_v1 = bytes[0..20];
        var sum_v1: u32 = 0;
        for (bytes_v1) |b|
            sum_v1 += b;
        if (sum_v1 & 0xFF != 0)
            return ParseError.InvalidChecksum;

        const bytes_v2 = bytes[20..36];
        var sum_v2: u32 = 0;
        for (bytes_v2) |b|
            sum_v2 += b;
        if (sum_v2 & 0xFF != 0)
            return ParseError.InvalidExtendedChecksum;

        return xsdp;
    }
};
comptime {
    assert(@sizeOf(XSDP) == 36);
    assert(@alignOf(XSDP) == 1);
}

/// System Description Table Header
pub const SDTH = extern struct {
    signiture: [4]u8 align(1),
    length: u32 align(1),
    revision: u8 align(1),
    checksum: u8 align(1),
    oem_id: [6]u8 align(1),
    oem_table_id: [8]u8 align(1),
    oen_revison: u32 align(1),
    creator_id: u32 align(1),
    creator_revison: u32 align(1),

    pub fn check(sdth: *const SDTH, signiture: []const u8) bool {
        if (!std.mem.eql(u8, &sdth.signiture, signiture))
            return false;

        const bytes: [*]const u8 = @ptrCast(sdth);
        var sum: u32 = 0;
        for (bytes[0..sdth.length]) |b|
            sum += b;
        if (sum & 0xFF != 0)
            return false;

        return true;
    }
};
comptime {
    assert(@sizeOf(SDTH) == 36);
    assert(@alignOf(SDTH) == 1);
}

/// Extended System Description Table
pub const XSDT = extern struct {
    header: SDTH align(1),

    pub const Iterator = struct {
        xsdt: *const XSDT,
        index: usize,
        pub fn next(it: *Iterator) ?*SDTH {
            const len = (it.xsdt.header.length - @sizeOf(SDTH)) / @sizeOf(u64);
            if (it.index < len) {
                const ptr: *align(1) u64 = @ptrFromInt(@intFromPtr(it.xsdt) + @sizeOf(SDTH) + it.index * @sizeOf(u64));
                it.index += 1;
                return @ptrFromInt(root.hal.page.direct_map_base + ptr.*);
            } else {
                return null;
            }
        }
    };
    pub inline fn iter(self: *const XSDT) Iterator {
        return .{
            .xsdt = self,
            .index = 0,
        };
    }
    pub fn find(self: *XSDT, T: type, signiture: []const u8) ?*T {
        assert(@alignOf(T) == 1);
        var it = self.iter();
        while (it.next()) |sdth| {
            if (sdth.check(signiture)) {
                return @ptrCast(sdth);
            }
        }
        return null;
    }
};
comptime {
    assert(@alignOf(XSDT) == 1);
}

/// Multiple APIC Description Table
/// See also: https://wiki.osdev.org/MADT
pub const MADT = extern struct {
    header: SDTH align(1),
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

pub const GenericAddress = extern struct {
    address_space_id: AddressSpace align(1),
    register_bit_width: u8 align(1),
    register_bit_offset: u8 align(1),
    access_size: u8 align(1),
    address: u64 align(1),

    pub const AddressSpace = enum(u8) {
        memory = 0,
        io_port = 1,
        _,
    };
    pub const AccessSize = enum(u8) {
        undefined = 0,
        @"8-bit" = 1,
        @"16-bit" = 2,
        @"32-bit" = 3,
        @"64-bit" = 4,
    };
};
comptime {
    assert(@alignOf(GenericAddress) == 1);
}

/// Fixed ACPI Description Table
pub const FADT = extern struct {
    header: SDTH align(1),
    firmware_ctrl: u32 align(1),
    dsdt: u32 align(1),

    // field used in ACPI 1.0; no longer in use, for compatibility only
    reserved: u8 align(1),

    preferred_power_management_profile: u8 align(1),
    sci_interrupt: u16 align(1),
    smi_command_port: u32 align(1),
    acpi_enable: u8 align(1),
    acpi_disable: u8 align(1),
    s4_bios_req: u8 align(1),
    pstate_control: u8 align(1),
    pm1a_event_block: u32 align(1),
    pm1b_event_block: u32 align(1),
    pm1a_control_block: u32 align(1),
    pm1b_control_block: u32 align(1),
    pm2_control_block: u32 align(1),
    pm_timer_block: u32 align(1),
    gpe0_block: u32 align(1),
    gpe1_block: u32 align(1),
    pm1_event_length: u8 align(1),
    pm1_control_length: u8 align(1),
    pm2_control_length: u8 align(1),
    pm_timer_length: u8 align(1),
    gpe0_length: u8 align(1),
    gpe1_length: u8 align(1),
    gpe1_base: u8 align(1),
    c_state_control: u8 align(1),
    worst_c2_latency: u16 align(1),
    worst_c3_latency: u16 align(1),
    flush_size: u16 align(1),
    flush_stride: u16 align(1),
    duty_offset: u8 align(1),
    duty_width: u8 align(1),
    day_alarm: u8 align(1),
    month_alarm: u8 align(1),
    century: u8 align(1),

    // reserved in ACPI 1.0; used since ACPI 2.0+
    boot_architecture_flags: u16 align(1),

    reserved2: u8 align(1),
    flags: u32 align(1),

    // 12 byte structure; see below for details
    reset_reg: GenericAddress align(1),

    reset_value: u8 align(1),
    reserved3: [3]u8 align(1),

    // 64bit pointers - Available on ACPI 2.0+
    x_firmware_control: u64 align(1),
    x_dsdt: u64 align(1),

    x_pm1a_event_block: GenericAddress align(1),
    x_pm1b_event_block: GenericAddress align(1),
    x_pm1a_control_block: GenericAddress align(1),
    x_pm1b_control_block: GenericAddress align(1),
    x_pm2_control_block: GenericAddress align(1),
    x_pm_timer_block: GenericAddress align(1),
    x_gpe0_block: GenericAddress align(1),
    x_gpe1_block: GenericAddress align(1),
};
comptime {
    assert(@alignOf(FADT) == 1);
}

/// High Precision Event Timer
pub const HPET = extern struct {
    header: SDTH align(1),
    hardware_rev_id: u8 align(1),
    flags: Flags align(1),
    pci_vendor_id: u16 align(1),
    address: GenericAddress align(1),
    hpet_number: u8 align(1),
    minimum_tick: u16 align(1),
    page_protection: u8 align(1),
    pub const Flags = packed struct(u8) {
        comparator_count: u5,
        counter_size: u1,
        reserved: u1,
        legacy_replacement: u1,
    };
};
