const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;

var kernel_page_table: ?PageTablePtr = null;
pub inline fn initKernelPageTable(gpa: std.mem.Allocator) !void {
    kernel_page_table = try .init(gpa);
}
pub inline fn getKernelPageTable() PageTablePtr {
    return kernel_page_table.?;
}

pub const PagingError = error{
    OutOfMemory,
    NotCanonical,
    AlreadyMapped,
    NotMapped,
};

pub const PageTablePtr = struct {
    const cpu = root.hal.cpu;
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
    const SpinLockIrq = root.sync.SpinLockIrq;
    const rmwPTE = page.rmwHardwarePTE;

    comptime {
        assert(entries_num * @sizeOf(PTE) == page_size);
    }

    global_table: *align(page_size) [entries_num]PTE,
    lock: *SpinLockIrq,
    cpus: std.ArrayList(cpu.CpuId), // TODO: TLB shootdown

    pub fn init(gpa: Allocator) PagingError!PageTablePtr {
        const global_table = try allocatePage(gpa);
        errdefer gpa.destroy(global_table);
        const lock = try gpa.create(SpinLockIrq);
        errdefer gpa.destroy(lock);
        lock.* = .unlocked;

        return .{
            .global_table = global_table,
            .lock = lock,
            .cpus = .empty,
        };
    }

    pub inline fn deinit(self: PageTablePtr, gpa: Allocator) void {
        _ = self.lock.lock();
        dfsFree(gpa, global_level, self.global_table);
        gpa.destroy(self.lock);
    }
    /// NOTE: Assume page table locked
    fn dfsFree(
        gpa: Allocator,
        level: PageLevel,
        table: *align(page_size) [entries_num]PTE,
    ) void {
        for (table) |*hardware_entry| {
            const entry = fromHardware(level, rmwPTE(hardware_entry));
            if (!entry.present or entry.type == .page) continue;
            const lower_table: *align(page_size) [entries_num]PTE = @ptrFromInt(phys2virt(entry.phys_addr));
            dfsFree(gpa, level.lower(), lower_table);
        }
        gpa.destroy(table);
    }

    /// Clone entries of global_level only.
    pub fn shallowClone(self: PageTablePtr, gpa: Allocator) PagingError!PageTablePtr {
        const new_page_table: PageTablePtr = try .init(gpa);
        errdefer new_page_table.deinit(gpa);
        @memcpy(new_page_table.global_table, self.global_table);
        return new_page_table;
    }

    pub fn clone(self: PageTablePtr, gpa: Allocator) PagingError!PageTablePtr {
        const lock_flag = self.lock.lock();
        defer self.lock.unlock(lock_flag);

        const new_lock = try gpa.create(SpinLockIrq);
        errdefer gpa.destroy(new_lock);
        new_lock.* = .unlocked;

        const result = dfsClone(gpa, global_level, self.global_table);
        if (result[0]) |new_table| {
            @branchHint(.likely);
            if (result[1]) |err| {
                @branchHint(.unlikely);
                dfsFree(gpa, global_level, new_table);
                return err;
            } else {
                @branchHint(.likely);
                return .{
                    .global_table = new_table,
                    .lock = new_lock,
                    .cpus = .empty,
                };
            }
        }
        return result[1].?;
    }
    /// NOTE: Assume page table locked
    /// Return value:
    ///   .{ table, null}  : succeeded
    ///   .{ table, error} : failed, caller free table
    ///   .{ null, error}  : failed
    fn dfsClone(
        gpa: Allocator,
        level: PageLevel,
        table: *align(page_size) const [entries_num]PTE,
    ) struct { ?*align(page_size) [entries_num]PTE, ?PagingError } {
        const new_table = allocatePage(gpa) catch |err| return .{ null, err };
        for (table, new_table) |hardware_entry, *new_hardware_entry| {
            var entry = fromHardware(level, hardware_entry);
            if (!entry.present) continue;
            if (entry.type == .table) {
                const lower_table: *align(page_size) const [entries_num]PTE = @ptrFromInt(phys2virt(entry.phys_addr));
                const result = dfsClone(gpa, level.lower(), lower_table);
                if (result[0]) |new_lower_table| {
                    @branchHint(.likely);
                    entry.phys_addr = virt2phys(@intFromPtr(new_lower_table));
                }
                if (result[1]) |err| {
                    @branchHint(.unlikely);
                    return .{ new_table, err };
                }
            }
            new_hardware_entry.* = toHardware(level, entry);
        }
        return .{ new_table, null };
    }

    pub fn map(
        self: PageTablePtr,
        gpa: Allocator,
        level: PageLevel,
        virt_addr: VirtAddr,
        phys_addr: PhysAddr,
        attr: PageAttribute,
    ) PagingError!void {
        const lock_flag = self.lock.lock();
        defer self.lock.unlock(lock_flag);

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
        atomicWrite(&current_table[idx], toHardware(current_level, .{
            .present = true,
            .phys_addr = phys_addr,
            .type = .page,
            .attribute = attr,
        }));
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

    pub fn unmap(
        self: PageTablePtr,
        gpa: Allocator,
        virt_addr: VirtAddr,
    ) PagingError!void {
        const lock_flag = self.lock.lock();
        defer self.lock.unlock(lock_flag);

        assert(virt_addr % page_size == 0);

        _ = gpa;
        @panic("TODO");
    }

    pub const QueryResult = struct {
        level: PageLevel,
        entry: PageTableEntry,
    };
    pub fn query(self: PageTablePtr, virt_addr: VirtAddr) ?QueryResult {
        const lock_flag = self.lock.lock();
        defer self.lock.unlock(lock_flag);

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

    /// MMU never acquire lock.
    /// So atomic release new value is necessary.
    inline fn atomicWrite(pte: *PTE, val: PTE) void {
        @atomicStore(PTE, pte, val, .release);
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
