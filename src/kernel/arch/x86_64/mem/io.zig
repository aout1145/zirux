const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const arch = root.arch.x86_64;

pub inline fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

pub inline fn outb(value: u8, port: u16) void {
    asm volatile (
        \\outb %[value], %[port]
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

pub inline fn read(T: type, addr: u64) T {
    assert(addr >= arch.mem.virtual_map_base and addr <= arch.mem.virtual_map_base + arch.mem.virtual_map_size);
    return asm volatile (
        \\mov (%[addr]), %[val]
        : [val] "=r" (-> T),
        : [addr] "r" (addr),
        : .{ .memory = true });
}

pub inline fn write(T: type, addr: u64, val: T) void {
    assert(addr >= arch.mem.virtual_map_base and addr <= arch.mem.virtual_map_base + arch.mem.virtual_map_size);
    asm volatile (
        \\mov %[val], (%[addr])
        :
        : [addr] "r" (addr),
          [val] "r" (val),
        : .{ .memory = true });
}
