const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;

var kernel_page_table_lock: root.sync.SpinLockIrq = .unlocked;
var kernel_page_table: ?PageTablePtr = null;

pub inline fn initKernelPageTable(gpa: std.mem.Allocator) !void {
    kernel_page_table = try .init(gpa);
}
pub inline fn getKernelPageTable(lock_flag: *u8) PageTablePtr {
    lock_flag.* = kernel_page_table_lock.lock();
    return kernel_page_table.?;
}
pub inline fn releaseKernelPageTable(lock_flag: u8) void {
    kernel_page_table_lock.unlock(lock_flag);
}

pub const PagingError = error{
    OutOfMemory,
    NotCanonical,
    AlreadyMapped,
    NotMapped,
};

pub const PageTablePtr = struct {
    const page = root.hal.page;
    const VirtAddr = page.VirtAddr;
    const PhysAddr = page.PhysAddr;
    const PTE = page.HardwarePTE;
    const entries_num = page.entries_num;
    const page_size = page.page_size;
    const global_level = page.global_level;
    const Allocator = std.mem.Allocator;
    const PageTableEntry = page.PageTableEntry;
    const PageAttribute = page.PageAttribute;
    const PageLevel = page.PageLevel;
    const fromHardware = page.fromHardwarePTE;
    const toHardware = page.toHardwarePTE;
    const flushTLB = page.flushTLB;

    comptime {
        assert(entries_num * @sizeOf(PTE) == page_size);
    }

    global_table: *align(page_size) [entries_num]PTE,

    pub fn init(gpa: Allocator) PagingError!PageTablePtr {
        return .{
            .global_table = try allocatePage(gpa),
        };
    }

    pub fn map(
        self: PageTablePtr,
        gpa: Allocator,
        level: PageLevel,
        virt_addr: VirtAddr,
        phys_addr: PhysAddr,
        attr: PageAttribute,
    ) PagingError!void {
        assert(level.pageSize() != null);
        assert(virt_addr % level.pageSize().? == 0);
        assert(phys_addr % level.pageSize().? == 0);
        // log.debug(@src(), "map {Bi}: 0x{x} -> 0x{x}", .{ level.pageSize().?, phys_addr, virt_addr });

        errdefer @panic("TODO: clean");

        var current_table: *align(page_size) [entries_num]PTE = self.global_table;
        var current_level: PageLevel = global_level;
        while (current_level != level) : (current_level = current_level.lower()) {
            const idx = current_level.index(virt_addr);
            var entry = fromHardware(current_level, current_table[idx]);
            if (!entry.present) {
                const new_table = try allocatePage(gpa);
                entry = .{
                    .present = true,
                    .phys_addr = virt2phys(@intFromPtr(new_table)),
                    .type = .table,
                };
                current_table[idx] = toHardware(current_level, entry);
            }
            if (entry.type == .page) {
                return PagingError.AlreadyMapped;
            }
            current_table = @ptrFromInt(phys2virt(entry.phys_addr));
        }

        const idx = current_level.index(virt_addr);
        const entry = fromHardware(current_level, current_table[idx]);
        if (entry.present) {
            return PagingError.AlreadyMapped;
        }
        current_table[idx] = toHardware(current_level, .{
            .present = true,
            .phys_addr = phys_addr,
            .type = .page,
            .attribute = attr,
        });
        flushTLB(virt_addr);
    }

    pub fn mapRange(
        self: PageTablePtr,
        gpa: Allocator,
        virt_addr: VirtAddr,
        phys_addr: PhysAddr,
        page_num: usize,
        attr: PageAttribute,
    ) PagingError!void {
        assert(virt_addr % page_size == 0);
        assert(phys_addr % page_size == 0);
        // log.debug(@src(), "mapRange: 0x{x} - 0x{x} -> 0x{x} - 0x{x}", .{
        //     virt_addr,
        //     virt_addr + page_num * page_size,
        //     phys_addr,
        //     phys_addr + page_num * page_size,
        // });

        errdefer @panic("TODO: clean");

        var offset: usize = 0;
        while (offset != page_num * page_size) {
            var level = global_level;
            while (true) : (level = level.lower()) {
                const level_page_size = level.pageSize() orelse continue;
                if ((virt_addr + offset) % level_page_size == 0 and (phys_addr + offset) % level_page_size == 0 and offset + level_page_size <= page_num * page_size) {
                    try self.map(gpa, level, virt_addr + offset, phys_addr + offset, attr);
                    offset += level_page_size;
                    break;
                }
            }
        }
    }

    pub const QueryResult = struct {
        level: PageLevel,
        entry: PageTableEntry,
    };
    pub fn query(self: PageTablePtr, virt_addr: VirtAddr) ?QueryResult {
        var current_table: *align(page_size) [entries_num]PTE = self.global_table;
        var current_level: PageLevel = global_level;
        while (true) : (current_level = current_level.lower()) {
            const idx = current_level.index(virt_addr);
            const entry = fromHardware(current_level, current_table[idx]);
            if (!entry.present) {
                return null;
            }
            if (entry.type == .page) {
                return .{
                    .level = current_level,
                    .entry = entry,
                };
            }
            current_table = @ptrFromInt(phys2virt(entry.phys_addr));

            if (current_level == .level1) break;
        }
        return null;
    }

    inline fn virt2phys(virt_addr: VirtAddr) PhysAddr {
        assert(virt_addr >= page.direct_map_base);
        assert(virt_addr < page.direct_map_base + page.direct_map_size);
        return virt_addr - page.direct_map_base;
    }
    inline fn phys2virt(phys_addr: PhysAddr) VirtAddr {
        return phys_addr + page.direct_map_base;
    }
    inline fn allocatePage(gpa: Allocator) PagingError!*align(page_size) [entries_num]PTE {
        const mem = try gpa.alignedAlloc(PTE, .fromByteUnits(page_size), entries_num);
        @memset(mem, 0);
        return @ptrCast(@alignCast(mem));
    }
};
