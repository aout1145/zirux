const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;

pub var xsdt: ?*tables.XSDT = null;

pub fn initFromUefiSystemTable(system_table: *std.os.uefi.tables.SystemTable) !void {
    const uefi = std.os.uefi;
    const config_table =
        system_table.configuration_table[0..system_table.number_of_table_entries];
    for (config_table) |entry| {
        if (entry.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            const xsdp = try tables.XSDP.parse(@intFromPtr(entry.vendor_table));
            xsdt = @ptrFromInt(root.hal.page.direct_map_base + xsdp.xsdt_address);
            if (xsdt.?.header.check("XSDT")) {
                return;
            }
        }
    }
    return error.NotFound;
}

pub const tables = @import("tables.zig");
pub const utils = @import("utils.zig");
