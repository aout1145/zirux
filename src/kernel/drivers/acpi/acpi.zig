const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;

pub var xsdt: ?*XSDT = null;

pub fn initFromUefiSystemTable(system_table: *std.os.uefi.tables.SystemTable) !void {
    const uefi = std.os.uefi;
    const config_table =
        system_table.configuration_table[0..system_table.number_of_table_entries];
    for (config_table) |entry| {
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            const xsdp = try XSDP.parse(@intFromPtr(entry.vendor_table));
            xsdt = @ptrFromInt(root.hal.page.direct_map_base + xsdp.xsdt_address);
            if (xsdt.?.header.check("XSDT")) {
                return;
            }
        }
    }
    return error.NotFound;
}

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

pub const tables = @import("tables.zig");
