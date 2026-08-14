const std = @import("std");
const root = @import("root");

const serial = @import("serial.zig");

var lock: root.sync.SpinLockIrq = .unlocked;
var serial_com1: ?serial.Writer = null;

pub fn init() void {
    serial_com1 = serial.init(.com1, 115200, &.{});
}

pub fn println(prefix: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
    const flag = lock.lock();
    defer lock.unlock(flag);

    if (serial_com1) |*writer| {
        if (prefix) |pre| {
            _ = writer.interface.write(pre) catch {};
        }
        writer.prefix = prefix;
        writer.interface.print(fmt, args) catch {};
        writer.prefix = null;
        writer.interface.writeByte('\n') catch {};
        writer.interface.flush() catch {};
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    asm volatile ("cli");

    println(null, "KERNEL PANIC: {s}", .{msg});

    var buffer: [256]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .allow_unsafe_unwind = true,
    }, &buffer);
    for (trace.return_addresses, 0..) |addr, idx| {
        println(null, " #{d:0>2}: 0x{X:0>16}", .{ idx, addr });
    }

    while (true)
        asm volatile ("hlt");
}
