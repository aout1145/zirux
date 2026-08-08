const std = @import("std");
const root = @import("root");
const arch_mem = root.arch.target.mem;
const assert = std.debug.assert;

pub const PhysAddr: type = arch_mem.PhysAddr;
pub const VirtAddr: type = arch_mem.VirtAddr;

// Direct mapping physical memory
pub const direct_map_base: PhysAddr = arch_mem.direct_map_base;
pub const direct_map_size: PhysAddr = arch_mem.direct_map_size;
// Indirect mapping physical memory
pub const virtual_map_base: PhysAddr = arch_mem.virtual_map_base;
pub const virtual_map_size: PhysAddr = arch_mem.virtual_map_size;
// Mapping areas that store page meta
pub const page_meta_base: PhysAddr = arch_mem.page_meta_base;
pub const page_meta_size: PhysAddr = arch_mem.page_meta_size;
// Kernel text/data space
pub const kernel_base: PhysAddr = arch_mem.kernel_base;
pub const kernel_size: PhysAddr = arch_mem.kernel_size;

pub const page_size: comptime_int = arch_mem.page.page_size;
pub const page_shift: comptime_int = arch_mem.page.page_shift;
pub const PageIndex: type = arch_mem.page.PageIndex;

pub const PageLevel = enum {
    level5,
    level4,
    level3,
    level2,
    level1,
    pub inline fn shift(self: PageLevel) std.math.Log2Int(PhysAddr) {
        return arch_mem.page.levelShift(self);
    }
    pub inline fn index(self: PageLevel, virt_addr: VirtAddr) usize {
        return arch_mem.page.levelIndex(self, virt_addr);
    }
    pub inline fn pageSize(self: PageLevel) ?usize {
        return arch_mem.page.levelPageSize(self);
    }
    pub inline fn lower(self: PageLevel) PageLevel {
        return switch (self) {
            .level5 => .level4,
            .level4 => .level3,
            .level3 => .level2,
            .level2 => .level1,
            .level1 => @panic("Reach the lowest"),
        };
    }
    pub inline fn upper(self: PageLevel) PageLevel {
        if (self == global_level) @panic("Reach the uppermost");
        return switch (self) {
            .level5 => unreachable,
            .level4 => .level5,
            .level3 => .level4,
            .level2 => .level3,
            .level1 => .level2,
        };
    }
};
pub const global_level: PageLevel = arch_mem.page.global_level;

pub const HardwarePTE: type = arch_mem.page.HardwarePTE;
pub const entries_num: comptime_int = arch_mem.page.entries_num;

pub const PageTableEntry = packed struct {
    present: bool,
    phys_addr: PhysAddr,
    /// When set to .table, page attributes will be ignored.
    type: PagingType,
    attribute: PageAttribute = .{
        .writable = true,
        .executable = true,
        .userspace = true,
        .global = false,
        .cache_policy = .write_back,
    },
};
pub const PageAttribute = packed struct {
    writable: bool,
    executable: bool,
    userspace: bool,
    global: bool,
    cache_policy: CachePolicy,
};
pub const PagingType = enum(u1) {
    page,
    table,
};
pub const CachePolicy = enum(u3) {
    uncacheable, // UC
    write_combining, // WC
    write_through, // WT
    write_protect, // WP
    write_back, // WB
    uncached, // UC-
};

pub inline fn fromHardwarePTE(level: PageLevel, pte: HardwarePTE) PageTableEntry {
    return arch_mem.page.fromHardwarePTE(level, pte);
}

pub inline fn toHardwarePTE(level: PageLevel, pte: PageTableEntry) HardwarePTE {
    return arch_mem.page.toHardwarePTE(level, pte);
}

pub inline fn readPagingBase() PhysAddr {
    return arch_mem.page.readPagingBase();
}
pub inline fn writePagingBase(phys_addr: PhysAddr) void {
    arch_mem.page.writePagingBase(phys_addr);
}
pub inline fn flushTLB(virt_addr: VirtAddr) void {
    arch_mem.page.flushTLB(virt_addr);
}
