const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;

const serial = @import("serial.zig");

var print_lock: root.sync.SpinLockIrq = .unlocked;
var serial_com1: ?serial.Writer = null;

pub fn init() void {
    serial_com1 = serial.init(.com1, 115200, &.{});
}

pub inline fn println(prefix: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
    const flag = print_lock.lock();
    defer print_lock.unlock(flag);
    printlnUnlocked(prefix, fmt, args);
}

fn printlnUnlocked(prefix: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
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

pub var panic_flag: std.atomic.Value(bool) = .init(false);
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    asm volatile ("cli");
    panic_flag.store(true, .release);
    @atomicStore(root.sync.SpinLockIrq, &print_lock, .locked, .release);

    arch.intr.ipi.sendRaw(0, 0, .others, .nmi);

    printlnUnlocked(null, "KERNEL PANIC on CPU#{} : {s}", .{ arch.cpu.per_cpu.getLcpuId(), msg });

    var buffer: [256]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .allow_unsafe_unwind = true,
    }, &buffer);
    for (trace.return_addresses, 0..) |addr, idx| {
        printlnUnlocked(null, " #{d:0>2}: 0x{X:0>16}", .{ idx, addr });
    }

    arch.cpu.endlessHalt();
}
