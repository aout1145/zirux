const std = @import("std");
const root = @import("root");
const hal = root.hal.page;
const arch = root.arch.x86_64;
const assert = std.debug.assert;

pub const page_size = 4096;
pub const page_shift = 12;
pub const HardwarePTE = u64;
pub const PageIndex = u52;
pub const global_level = hal.PageLevel.level4;
pub const entries_num = 512;

pub fn init() void {
    const @"asm" = arch.@"asm";
    const registers = @"asm".registers;

    var efer = @"asm".readCtrlMsr(registers.Efer, registers.Efer.msr);
    efer.nxe = true;
    @"asm".writeCtrlMsr(registers.Efer.msr, efer);

    @"asm".writeMsr(registers.Pat.msr, pat_msr_value);

    var cr4 = @"asm".readCtrlRegister(registers.Cr4, "cr4");
    // cr4.smep = true;
    // cr4.smap = true;
    cr4.pse = true;
    cr4.pge = true;
    @"asm".writeCtrlRegister("cr4", cr4);
}

pub inline fn levelShift(level: hal.PageLevel) std.math.Log2Int(hal.PhysAddr) {
    return switch (level) {
        .level1 => 12,
        .level2 => 21,
        .level3 => 30,
        .level4 => 39,
        .level5 => 48,
    };
}

pub inline fn levelIndex(level: hal.PageLevel, virt_addr: hal.VirtAddr) usize {
    const index_mask = 0x1FF;
    return @intCast(index_mask & (virt_addr >> levelShift(level)));
}

pub inline fn levelPageSize(level: hal.PageLevel) ?usize {
    const mem = root.mem;
    return switch (level) {
        .level1 => 4 * mem.kib,
        .level2 => 2 * mem.mib,
        .level3 => 1 * mem.gib,
        else => null,
    };
}

pub const Entry = packed struct(HardwarePTE) {
    present: bool,
    _reserved0: u6,
    ps: bool,
    _reserved1: u56,
};

pub const Page4Kib = packed struct(HardwarePTE) {
    /// Present.
    present: bool,
    /// Read/Write.
    rw: bool,
    /// User/Supervisor.
    us: bool,
    /// Write Through.
    pwt: bool,
    /// Cache Diable.
    pcd: bool,
    /// Accessed.
    accessed: bool = false,
    /// Dirty.
    dirty: bool = false,
    /// Page Attribute Table
    pat: bool,
    /// Global.
    global: bool,
    /// Ignored.
    _ignored1: u3 = 0,
    /// Physical Address (Bit 12-51)
    phys: u40,
    /// Ignored.
    _ignored2: u7 = 0,
    /// Protection Key.
    pk: u4,
    /// Execute Disable.
    xd: bool,
};

pub const Page2Mib = packed struct(HardwarePTE) {
    /// Present.
    present: bool,
    /// Read/Write.
    rw: bool,
    /// User/Supervisor.
    us: bool,
    /// Write Through.
    pwt: bool,
    /// Cache Diable.
    pcd: bool,
    /// Accessed.
    accessed: bool = false,
    /// Dirty.
    dirty: bool = false,
    /// Page Size. Must be true.
    ps: bool = true,
    /// Global.
    global: bool,
    /// Ignored.
    _ignored1: u3 = 0,
    /// Page Attribute Table
    pat: bool,
    /// Reserved.
    _reserved: u8 = 0,
    /// Physical Address (Bit 21-51)
    phys: u31,
    /// Ignored.
    _ignored2: u7 = 0,
    /// Protection Key.
    pk: u4,
    /// Execute Disable.
    xd: bool,
};

pub const Page1Gib = packed struct(HardwarePTE) {
    /// Present.
    present: bool,
    /// Read/Write.
    rw: bool,
    /// User/Supervisor.
    us: bool,
    /// Write Through.
    pwt: bool,
    /// Cache Diable.
    pcd: bool,
    /// Accessed.
    accessed: bool = false,
    /// Dirty.
    dirty: bool = false,
    /// Page Size. Must be true.
    ps: bool = true,
    /// Global.
    global: bool,
    /// Ignored.
    _ignored1: u3 = 0,
    /// Page Attribute Table
    pat: bool,
    /// Reserved.
    _reserved: u17 = 0,
    /// Physical Address (Bit 30-51)
    phys: u22,
    /// Ignored.
    _ignored2: u7 = 0,
    /// Protection Key.
    pk: u4,
    /// Execute Disable.
    xd: bool,
};

pub const Table = packed struct(HardwarePTE) {
    /// Present.
    present: bool,
    /// Read/Write.
    rw: bool,
    /// User/Supervisor.
    us: bool,
    /// Write Through.
    pwt: bool,
    /// Cache Diable.
    pcd: bool,
    /// Accessed.
    accessed: bool = false,
    /// Ignored.
    _ignored1: u1 = 0,
    /// Page Size. Must be false.
    ps: bool = false,
    /// Ignored.
    _ignored2: u4 = 0,
    /// Physical Address (Bit 12-51)
    phys: u40,
    /// Ignored.
    _ignored3: u11 = 0,
    /// Execute Disable.
    xd: bool,
};

// PAT PCD PWT Type
//  0   0   0  WB  6
//  0   0   1  WT  4
//  0   1   0  UC- 7
//  0   1   1  UC  0
//  1   0   0  WC  1
//  1   0   1  WP  5
//  1   1   0  reserved
//  1   1   1  reserved
const pat_msr_value = 0x00_00_05_01_00_07_04_06;
fn toCachePolicy(pat: bool, pcd: bool, pwt: bool) hal.CachePolicy {
    const index2pat: [6]hal.CachePolicy = .{
        .write_back,
        .write_through,
        .uncached,
        .uncacheable,
        .write_combining,
        .write_protect,
    };
    const i_2: u3 = @intFromBool(pat);
    const i_1: u3 = @intFromBool(pcd);
    const i_0: u3 = @intFromBool(pwt);
    return index2pat[(i_2 << 2) | (i_1 << 1) | i_0];
}
fn fromCachePolicy(cache_policy: hal.CachePolicy) [3]bool {
    return switch (cache_policy) {
        .write_back => .{ false, false, false },
        .write_through => .{ false, false, true },
        .uncached => .{ false, true, false },
        .uncacheable => .{ false, true, true },
        .write_combining => .{ true, false, false },
        .write_protect => .{ true, false, true },
    };
}

pub fn fromHardwarePTE(level: hal.PageLevel, pte: HardwarePTE) hal.PageTableEntry {
    const entry: Entry = @bitCast(pte);

    switch (level) {
        .level1 => {
            const page: Page4Kib = @bitCast(pte);
            return .{
                .present = page.present,
                .phys_addr = @as(u64, page.phys) << levelShift(.level1),
                .type = .page,
                .attribute = .{
                    .writable = page.rw,
                    .executable = !page.xd,
                    .userspace = page.us,
                    .global = page.global,
                    .cache_policy = toCachePolicy(page.pat, page.pcd, page.pwt),
                },
            };
        },
        .level2 => if (entry.ps) {
            const page: Page2Mib = @bitCast(pte);
            return .{
                .present = page.present,
                .phys_addr = @as(u64, page.phys) << levelShift(.level2),
                .type = .page,
                .attribute = .{
                    .writable = page.rw,
                    .executable = !page.xd,
                    .userspace = page.us,
                    .global = page.global,
                    .cache_policy = toCachePolicy(page.pat, page.pcd, page.pwt),
                },
            };
        },
        .level3 => if (entry.ps) {
            const page: Page1Gib = @bitCast(pte);
            return .{
                .present = page.present,
                .phys_addr = @as(u64, page.phys) << levelShift(.level3),
                .type = .page,
                .attribute = .{
                    .writable = page.rw,
                    .executable = !page.xd,
                    .userspace = page.us,
                    .global = page.global,
                    .cache_policy = toCachePolicy(page.pat, page.pcd, page.pwt),
                },
            };
        },
        .level4 => assert(entry.ps == false),
        else => unreachable,
    }

    const table: Table = @bitCast(pte);
    return .{
        .present = table.present,
        .phys_addr = @as(u64, table.phys) << page_shift,
        .type = .table,
        .attribute = .{
            .writable = true,
            .executable = true,
            .userspace = true,
            .global = false,
            .cache_policy = toCachePolicy(false, table.pcd, table.pwt),
        },
    };
}

pub fn toHardwarePTE(level: hal.PageLevel, pte: hal.PageTableEntry) HardwarePTE {
    const isAlignedLog2 = std.mem.isAlignedLog2;
    const pat = fromCachePolicy(pte.attribute.cache_policy);

    switch (level) {
        .level1 => {
            assert(pte.type == .page);
            assert(isAlignedLog2(pte.phys_addr, levelShift(.level1)));
            return @bitCast(Page4Kib{
                .present = pte.present,
                .phys = @truncate(pte.phys_addr >> page_shift),
                .rw = pte.attribute.writable,
                .xd = !pte.attribute.executable,
                .us = pte.attribute.userspace,
                .global = pte.attribute.global,
                .pat = pat[0],
                .pcd = pat[1],
                .pwt = pat[2],
                .pk = 0,
            });
        },
        .level2 => if (pte.type == .page) {
            assert(isAlignedLog2(pte.phys_addr, levelShift(.level2)));
            return @bitCast(Page2Mib{
                .present = pte.present,
                .phys = @truncate(pte.phys_addr >> levelShift(.level2)),
                .rw = pte.attribute.writable,
                .xd = !pte.attribute.executable,
                .us = pte.attribute.userspace,
                .global = pte.attribute.global,
                .pat = pat[0],
                .pcd = pat[1],
                .pwt = pat[2],
                .pk = 0,
            });
        },
        .level3 => if (pte.type == .page) {
            assert(isAlignedLog2(pte.phys_addr, levelShift(.level3)));
            return @bitCast(Page1Gib{
                .present = pte.present,
                .phys = @truncate(pte.phys_addr >> levelShift(.level3)),
                .rw = pte.attribute.writable,
                .xd = !pte.attribute.executable,
                .us = pte.attribute.userspace,
                .global = pte.attribute.global,
                .pat = pat[0],
                .pcd = pat[1],
                .pwt = pat[2],
                .pk = 0,
            });
        },
        .level4 => assert(pte.type == .table),
        else => unreachable,
    }

    // Ignore all page attributes
    assert(isAlignedLog2(pte.phys_addr, page_shift));
    return @bitCast(Table{
        .present = pte.present,
        .phys = @truncate(pte.phys_addr >> page_shift),
        .rw = true,
        .xd = false,
        .us = true,
        .pcd = false,
        .pwt = false,
    });
}

pub inline fn rmwHardwarePTE(pte: *HardwarePTE) HardwarePTE {
    return @atomicRmw(HardwarePTE, pte, .Xchg, 0, .acq_rel);
}

pub inline fn readPagingBase() hal.PhysAddr {
    const cr3 = arch.@"asm".readCtrlRegister(arch.@"asm".registers.Cr3, "cr3");
    return @as(u64, cr3.phys) << page_shift;
}
pub inline fn writePagingBase(phys_addr: hal.PhysAddr) void {
    assert(std.mem.isAlignedLog2(phys_addr, page_shift));
    var cr3 = arch.@"asm".readCtrlRegister(arch.@"asm".registers.Cr3, "cr3");
    cr3.phys = @truncate(phys_addr >> page_shift);
    arch.@"asm".writeCtrlRegister("cr3", cr3);
}
pub inline fn flushTLB(virt_addr: hal.VirtAddr) void {
    assert(virt_addr % page_size == 0);
    asm volatile (
        \\invlpg (%[virt])
        :
        : [virt] "r" (virt_addr),
        : .{ .memory = true });
}
