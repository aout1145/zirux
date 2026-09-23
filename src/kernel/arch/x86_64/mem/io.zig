const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const arch = root.arch.x86_64;
const hal = root.hal;

fn genMmioRead(T: type) *const fn (addr: usize) T {
    return struct {
        pub fn read(addr: usize) T {
            return asm volatile (
                \\mov (%[addr]), %[value]
                : [value] "=r" (-> T),
                : [addr] "r" (addr),
                : .{ .memory = true });
        }
    }.read;
}
fn genMmioWrite(T: type) *const fn (addr: usize, value: T) void {
    return struct {
        pub fn write(addr: usize, value: T) void {
            return asm volatile (
                \\mov %[value], (%[addr])
                :
                : [addr] "r" (addr),
                  [value] "r" (value),
                : .{ .memory = true });
        }
    }.write;
}
pub const mmio_vtable: hal.io.IoRegion.VTable = .{
    .read8 = genMmioRead(u8),
    .read16 = genMmioRead(u16),
    .read32 = genMmioRead(u32),
    .read64 = genMmioRead(u64),
    .write8 = genMmioWrite(u8),
    .write16 = genMmioWrite(u16),
    .write32 = genMmioWrite(u32),
    .write64 = genMmioWrite(u64),
};

pub fn inb(port: usize) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn outb(value: u8, port: usize) void {
    asm volatile (
        \\outb %[value], %[port]
        :
        : [value] "{al}" (value),
          [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn inw(port: usize) u16 {
    return asm volatile (
        \\inw %[port], %[ret]
        : [ret] "={ax}" (-> u16),
        : [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn outw(value: u16, port: usize) void {
    asm volatile (
        \\outw %[value], %[port]
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn inl(port: usize) u32 {
    return asm volatile (
        \\inl %[port], %[ret]
        : [ret] "={eax}" (-> u32),
        : [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn outl(value: u32, port: usize) void {
    asm volatile (
        \\outl %[value], %[port]
        :
        : [value] "{eax}" (value),
          [port] "{dx}" (@as(u16, @intCast(port))),
    );
}
pub fn inq(_: usize) u64 {
    unreachable;
}
pub fn outq(_: u64, _: usize) void {
    unreachable;
}
pub const ioport_vtable: hal.io.IoRegion.VTable = .{
    .read8 = inb,
    .read16 = inw,
    .read32 = inl,
    .read64 = inq,
    .write8 = outb,
    .write16 = outl,
    .write32 = outw,
    .write64 = outq,
};
