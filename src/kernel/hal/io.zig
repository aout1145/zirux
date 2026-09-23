const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;
const assert = std.debug.assert;

pub const IoRegion = struct {
    base: hal.page.VirtAddr,
    len: usize,
    vtable: *const VTable,

    pub const VTable = struct {
        read8: *const fn (addr: usize) u8,
        read16: *const fn (addr: usize) u16,
        read32: *const fn (addr: usize) u32,
        read64: *const fn (addr: usize) u64,
        write8: *const fn (addr: usize, value: u8) void,
        write16: *const fn (addr: usize, value: u16) void,
        write32: *const fn (addr: usize, value: u32) void,
        write64: *const fn (addr: usize, value: u64) void,
    };

    pub inline fn read8(self: IoRegion, offset: usize) u8 {
        assert(offset <= self.len);
        return self.vtable.read8(self.base + offset);
    }
    pub inline fn read16(self: IoRegion, offset: usize) u16 {
        assert(offset <= self.len);
        return self.vtable.read16(self.base + offset);
    }
    pub inline fn read32(self: IoRegion, offset: usize) u32 {
        assert(offset <= self.len);
        return self.vtable.read32(self.base + offset);
    }
    pub inline fn read64(self: IoRegion, offset: usize) u64 {
        assert(offset <= self.len);
        return self.vtable.read64(self.base + offset);
    }
    pub inline fn write8(self: IoRegion, offset: usize, value: u8) void {
        assert(offset <= self.len);
        self.vtable.write8(self.base + offset, value);
    }
    pub inline fn write16(self: IoRegion, offset: usize, value: u16) void {
        assert(offset <= self.len);
        self.vtable.write16(self.base + offset, value);
    }
    pub inline fn write32(self: IoRegion, offset: usize, value: u32) void {
        assert(offset <= self.len);
        self.vtable.write32(self.base + offset, value);
    }
    pub inline fn write64(self: IoRegion, offset: usize, value: u64) void {
        assert(offset <= self.len);
        self.vtable.write64(self.base + offset, value);
    }
};

const mmio_vtable: IoRegion.VTable = arch.mem.io.mmio_vtable;
pub fn initMemMapIo(base: hal.page.VirtAddr, len: usize) IoRegion {
    return .{
        .base = base,
        .len = len,
        .vtable = &mmio_vtable,
    };
}

const ioport_vtable: ?IoRegion.VTable = if (@hasDecl(arch.mem.io, "ioport_vtable"))
    arch.mem.io.mmio_vtable
else
    null;
pub fn initIoPort(base: hal.page.VirtAddr, len: usize) IoRegion {
    return .{
        .base = base,
        .len = len,
        .vtable = &ioport_vtable.?,
    };
}
