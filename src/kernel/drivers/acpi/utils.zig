const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;
const assert = std.debug.assert;
const hal = root.hal;
const mem = root.mem;

pub fn mapAddress(gas: acpi.tables.GenericAddress, map_size: ?usize) !hal.io.IoRegion {
    const len = if (gas.register_bit_offset > 0)
        (gas.register_bit_offset + gas.register_bit_width + 7) / 8
    else
        map_size.?;
    return switch (gas.address_space_id) {
        .memory => mem.vmap.ioMap(gas.address, len, .write_back),
        .io_port => hal.io.initIoPort(gas.address, len),
        else => unreachable,
    };
}
