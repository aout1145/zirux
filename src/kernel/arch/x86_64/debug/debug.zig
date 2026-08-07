const std = @import("std");
const root = @import("root");

const serial = @import("serial.zig");

const serial_port: serial.Ports = .com1;
const serial_baud: u32 = 115200;
var serial_available: std.atomic.Value(bool) = .init(false);

pub fn init() void {
    serial_available.store(serial.init(serial_port, serial_baud), .monotonic);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    const str = std.fmt.bufPrint(&buffer, fmt, args) catch blk: {
        buffer[buffer.len - 1] = '\n';
        buffer[buffer.len - 2] = '.';
        buffer[buffer.len - 3] = '.';
        buffer[buffer.len - 4] = '.';
        break :blk &buffer;
    };
    // print to serial
    if (serial_available.load(.acquire)) {
        for (str) |byte| {
            serial.write(byte, serial_port);
        }
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    asm volatile ("cli");

    print("KERNEL PANIC: {s}\n", .{msg});

    var buffer: [256]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .allow_unsafe_unwind = true,
    }, &buffer);
    for (trace.return_addresses, 0..) |addr, idx| {
        print(" #{d:0>2}: 0x{X:0>16}\n", .{ idx, addr });
    }

    while (true)
        asm volatile ("hlt");
}
