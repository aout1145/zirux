const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;

pub const serial = @import("serial.zig");
pub const framebuffer = @import("framebuffer.zig");

var print_lock: root.sync.SpinLockIrq = .unlocked;

/// Print `fmt` to every debug sink, writing `prefix` at the start of each line.
pub inline fn println(prefix: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
    if (panic_flag.load(.acquire)) {
        printlnUnlocked(prefix, fmt, args);
    } else {
        const flag = print_lock.lock();
        defer print_lock.unlock(flag);
        printlnUnlocked(prefix, fmt, args);
    }
}

fn printlnUnlocked(prefix: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
    if (prefix) |pre| writeRaw(pre);

    var buffer: [64]u8 = undefined;
    var prefixed: PrefixWriter = .{
        .prefix = prefix,
        .at_line_start = false,
        .interface = .{
            .buffer = &buffer,
            .vtable = &PrefixWriter.vtable,
        },
    };
    prefixed.interface.print(fmt, args) catch {};
    prefixed.interface.flush() catch {};

    // Final newline is not prefixed.
    writeByteRaw('\n');
}

fn writeRaw(bytes: []const u8) void {
    if (serial.writer) |w| w.writeAll(bytes) catch {};
    if (framebuffer.writer) |w| w.writeAll(bytes) catch {};
}
fn writeByteRaw(byte: u8) void {
    if (serial.writer) |w| w.writeByte(byte) catch {};
    if (framebuffer.writer) |w| w.writeByte(byte) catch {};
}

/// Inserts `prefix` at the start of each line and fans out to the sinks.
const PrefixWriter = struct {
    interface: std.Io.Writer,
    prefix: ?[]const u8,
    at_line_start: bool,

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *PrefixWriter = @fieldParentPtr("interface", w);
        self.writeSlices(w.buffer[0..w.end]);
        w.end = 0;

        var written: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            self.writeSlices(bytes);
            written += bytes.len;
        }
        for (0..splat) |_| {
            const bytes = data[data.len - 1];
            self.writeSlices(bytes);
            written += bytes.len;
        }
        return written;
    }

    fn writeSlices(self: *PrefixWriter, bytes: []const u8) void {
        for (bytes) |byte| {
            if (self.at_line_start) {
                if (self.prefix) |pre| writeRaw(pre);
                self.at_line_start = false;
            }
            writeByteRaw(byte);
            if (byte == '\n') self.at_line_start = true;
        }
    }

    const vtable: std.Io.Writer.VTable = .{ .drain = drain };
};

pub var panic_flag: std.atomic.Value(bool) = .init(false);
pub inline fn setPanicFlag() void {
    panic_flag.store(true, .release);
}
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    asm volatile ("cli");
    panic_flag.store(true, .release);
    @atomicStore(root.sync.SpinLockIrq, &print_lock, .locked, .release);

    if (arch.cpu.smp.all_finished.load(.acquire)) {
        arch.intr.ipi.sendRaw(0, 0, .others, .nmi);
    }

    printlnUnlocked(null, "\nKERNEL PANIC on CPU#{} : {s}", .{ arch.cpu.per_cpu.getLocalCpuId(), msg });

    var buffer: [256]usize = undefined;
    const trace = std.debug.captureCurrentStackTrace(.{
        .allow_unsafe_unwind = true,
    }, &buffer);
    for (trace.return_addresses, 0..) |addr, idx| {
        printlnUnlocked(null, " #{d:0>2}: 0x{X:0>16}", .{ idx, addr });
    }

    arch.cpu.endlessHalt();
}
