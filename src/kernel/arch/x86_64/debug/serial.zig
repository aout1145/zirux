const std = @import("std");
const root = @import("root");
const @"asm" = root.arch.x86_64.@"asm";

pub const Ports = enum(u16) {
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

/// True if initialization successfully
pub fn init(port: Ports, baud: u32) bool {
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
        return false;
    }
    @"asm".outb(0b00001111, p + offsets.mcr);

    return true;
}

pub fn write(byte: u8, port: Ports) void {
    const p = @intFromEnum(port);
    // Wait until the transmitter holding buffer is empty
    while ((@"asm".inb(p + offsets.lsr) & 0b0010_0000) == 0) {
        @"asm".pause();
    }
    // Put char into the transmitter holding buffer
    @"asm".outb(byte, p);
}
