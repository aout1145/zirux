const std = @import("std");
const root = @import("root");
const @"asm" = root.arch.x86_64.@"asm";

pub const Port = enum(u16) {
    com1 = 0x3F8,
    com2 = 0x2F8,
    com3 = 0x3E8,
    com4 = 0x2E8,
    com5 = 0x5F8,
    com6 = 0x4F8,
    com7 = 0x5E8,
    com8 = 0x4E8,
};

/// See also: https://wiki.osdev.org/Serial_Ports
const offsets = struct {
    /// Transmitter Holding Buffer: DLAB=0, W
    pub const txr = 0;
    /// Receiver Buffer: DLAB=0, R
    pub const rxr = 0;
    /// Divisor Latch Low Byte: DLAB=1, R/W
    pub const dll = 0;
    /// Interrupt Enable Register: DLAB=0, R/W
    pub const ier = 1;
    /// Divisor Latch High Byte: DLAB=1, R/W
    pub const dlh = 1;
    /// Interrupt Identification Register: DLAB=X, R
    pub const iir = 2;
    /// FIFO Control Register: DLAB=X, W
    pub const fcr = 2;
    /// Line Control Register: DLAB=X, R/W
    pub const lcr = 3;
    /// Modem Control Register: DLAB=X, R/W
    pub const mcr = 4;
    /// Line Status Register: DLAB=X, R
    pub const lsr = 5;
    /// Modem Status Register: DLAB=X, R
    pub const msr = 6;
    /// Scratch Register: DLAB=X, R/W
    pub const sr = 7;
};

pub fn init(port: Port, baud: u32, buffer: []u8) ?Writer {
    const p = @intFromEnum(port);

    @"asm".outb(0, p + offsets.ier); // Disable interrupts
    @"asm".outb(0, p + offsets.fcr); // Disable FIFO

    const divisor = 115200 / baud;
    const c = @"asm".inb(p + offsets.lcr);
    @"asm".outb(c | 0b1000_0000, p + offsets.lcr); // Enable DLAB
    @"asm".outb(@truncate(divisor), p + offsets.dll);
    @"asm".outb(@truncate(divisor >> 8), p + offsets.dlh);

    // Disable DLAB
    // 8n1: no parity, 1 stop bit, 8 data bit
    @"asm".outb(0b00_000_0_11, p + offsets.lcr);

    // Set in loopback mode, test the serial chip
    @"asm".outb(0b00011111, p + offsets.mcr);
    @"asm".outb(0xAE, p);
    if (@"asm".inb(p) != 0xAE) {
        return null;
    }
    @"asm".outb(0b00001111, p + offsets.mcr);

    return .{
        .port = port,
        .prefix = null,
        .interface = .{
            .buffer = buffer,
            .vtable = &Writer.vtable,
        },
    };
}

fn write(byte: u8, port: Port) void {
    const p = @intFromEnum(port);
    // Wait until the transmitter holding buffer is empty
    while ((@"asm".inb(p + offsets.lsr) & 0b0010_0000) == 0) {
        @"asm".pause();
    }
    // Put char into the transmitter holding buffer
    @"asm".outb(byte, p);
}

pub const Writer = struct {
    port: Port,
    prefix: ?[]const u8,
    interface: std.Io.Writer,

    fn writeStr(self: *const Writer, str: []const u8) void {
        for (str) |byte| {
            write(byte, self.port);
            if (byte == '\n') {
                if (self.prefix) |pre| {
                    for (pre) |prebyte| {
                        write(prebyte, self.port);
                    }
                }
            }
        }
    }
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *const Writer = @fieldParentPtr("interface", w);
        self.writeStr(w.buffer[0..w.end]);
        w.end = 0;
        var num: usize = 0;
        for (data[0 .. data.len - 1]) |buf| {
            self.writeStr(buf);
            num += buf.len;
        }
        for (0..splat) |_| {
            const buf = data[data.len - 1];
            self.writeStr(buf);
            num += buf.len;
        }
        return num;
    }
    pub const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
    };
};
