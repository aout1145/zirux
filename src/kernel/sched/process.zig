const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const hal = root.hal;
const utils = root.utils;
const sync = root.sync;
const mem = root.mem;
const fs = root.fs;
const allocator = mem.general_allocator;

const thread = @import("thread.zig");

pub const ProcessId = u32;
pub const Process = struct {
    _refcount: u32,

    proc_name: [8]u8,
    proc_id: ProcessId,

    page_table: mem.page_table.PageTablePtr,
    thrd_ids: std.ArrayList(thread.ThreadId),
    pages: std.ArrayList(hal.page.PageIndex),

    pub inline fn ref(self: *Process) void {
        return sync.ref(u32, &self._refcount);
    }
    pub inline fn unref(self: *Process) void {
        if (sync.unref(u32, &self._refcount)) {
            @panic("TODO: clean");
        }
    }
};

const init_proc_cpu = 0;
var idle_created: std.atomic.Value(bool) = .init(false);
var process_lock: sync.SpinLockIrq = .unlocked;
var processes: utils.IdAllocator(ProcessId, Process) = .empty;

pub inline fn init() !void {
    try initIdleProc();
    try initInitProc();

    // var test_file = try fs.open("/init", .{ .seekable = true });
    // defer fs.close(&test_file) catch {};
    // _ = try createProcess(&test_file, .{
    //     .proc_name = "TEST".* ++ .{0} ** 4,
    // });
}

fn initIdleProc() !void {
    if (hal.cpu.getLocalCpuId() == init_proc_cpu) {
        const lock_flag = process_lock.lock();
        defer process_lock.unlock(lock_flag);

        // Create IDLE(0) process
        const idle_pid = try processes.alloc(allocator);
        assert(idle_pid == 0);
        const idle_proc = processes.get(idle_pid).?;
        idle_proc.* = .{
            ._refcount = 1,
            .proc_name = "IDLE".* ++ .{0} ** 4,
            .proc_id = idle_pid,
            .page_table = mem.page_table.getKernelPageTableUnlocked(), // Directly use kernel page table
            .thrd_ids = .empty,
            .pages = .empty,
        };

        idle_created.store(true, .release);
    }
    // Wait for IDLE being created
    while (!idle_created.load(.acquire)) {
        hal.sync.spinHint();
    }

    const lock_flag = process_lock.lock();
    defer process_lock.unlock(lock_flag);
    const idle_proc = processes.get(0).?;
    try idle_proc.thrd_ids.append(allocator, try thread.init(idle_proc));
}

fn initInitProc() !void {
    if (hal.cpu.getLocalCpuId() == init_proc_cpu) {
        // Create INIT(1) process
        var init_file = try fs.open("/init", .{ .seekable = true });
        // log.debug(@src(), "0", .{});
        defer fs.close(&init_file) catch {};
        const init_pid = try createProcess(&init_file, .{
            .proc_name = "INIT".* ++ .{0} ** 4,
        });
        assert(init_pid == 1);
    }
}

pub const Options = struct {
    proc_name: [8]u8,
};
pub fn createProcess(file: *fs.File, options: Options) !ProcessId {
    const pt = blk: {
        var lock_flag: u8 = undefined;
        const kernel_page_table = mem.page_table.getKernelPageTable(&lock_flag);
        defer mem.page_table.releaseKernelPageTable(lock_flag);
        break :blk try kernel_page_table.clone(allocator);
    };
    errdefer pt.deinit();

    // log.debug(@src(), "1", .{});
    var pages: std.ArrayList(hal.page.PageIndex) = .empty;
    errdefer {
        for (pages.items) |page_index| {
            mem.buddy.unref(page_index);
        }
        pages.deinit(allocator);
    }

    // log.debug(@src(), "2", .{});
    const header_buffer = try allocator.alloc(u8, @sizeOf(std.elf.Elf64_Ehdr));
    defer allocator.free(header_buffer);
    const header_read_size = try fs.read(file, 0, header_buffer);
    var header_reader = std.Io.Reader.fixed(header_buffer[0..header_read_size]);
    const header = try std.elf.Header.read(&header_reader);

    var iter = ProgramHeaderIterator.init(header, file);
    while (try iter.next()) |phdr| if (phdr.p_type == std.elf.PT_LOAD) {
        assert(phdr.p_offset % hal.page.page_size == 0);
        assert(phdr.p_vaddr % hal.page.page_size == 0);

        const page_count = (phdr.p_memsz + hal.page.page_size - 1) / hal.page.page_size;
        try pages.ensureUnusedCapacity(allocator, page_count);
        for (0..page_count) |i| {
            const page_index = mem.buddy.alloc(0, .user) orelse return error.OutOfMemory;
            pages.appendAssumeCapacity(page_index);
            const page: *[hal.page.page_size]u8 = @ptrFromInt(hal.page.index2addr(page_index) + hal.page.direct_map_base);
            @memset(page, 0);
            _ = try fs.read(file, phdr.p_offset + i * hal.page.page_size, page);
            // log.debug(@src(), "mapped {x}", .{phdr.p_vaddr + i * hal.page.page_size});
            try pt.map(
                allocator,
                .level1,
                phdr.p_vaddr + i * hal.page.page_size,
                hal.page.index2addr(page_index),
                .{
                    .userspace = true,
                    .global = false,
                    .executable = phdr.p_flags & std.elf.PF_X != 0,
                    .writable = phdr.p_flags & std.elf.PF_W != 0,
                    .cache_policy = .write_back,
                },
            );
        }
    };

    // log.debug(@src(), "3", .{});
    const lock_flag = process_lock.lock();
    defer process_lock.unlock(lock_flag);
    const pid = try processes.alloc(allocator);
    errdefer processes.free(allocator, pid) catch {};
    const proc = processes.get(pid).?;
    proc.* = .{
        ._refcount = 1,
        .proc_name = options.proc_name,
        .proc_id = pid,
        .page_table = pt,
        .thrd_ids = .empty,
        .pages = pages,
    };
    try proc.thrd_ids.ensureUnusedCapacity(allocator, 1);
    errdefer proc.thrd_ids.deinit(allocator);

    const tid = try thread.createThread(proc, header.entry, .{});
    proc.thrd_ids.appendAssumeCapacity(tid);

    proc.unref();
    return pid;
}

const ProgramHeaderIterator = struct {
    elf_header: std.elf.Header,
    file: *fs.File,
    index: usize = 0,
    pub fn init(elf_header: std.elf.Header, file: *fs.File) @This() {
        return .{ .elf_header = elf_header, .file = file };
    }
    /// support 64-bit only
    pub fn next(it: *@This()) !?std.elf.Elf64_Phdr {
        if (it.index >= it.elf_header.phnum) return null;
        defer it.index += 1;

        const size: u64 = @sizeOf(std.elf.Elf64_Phdr);
        const offset = it.elf_header.phoff + size * it.index;
        var phdr: std.elf.Elf64_Phdr = undefined;
        const buffer: [*]u8 = @ptrCast(&phdr);
        _ = try fs.read(it.file, offset, buffer[0..size]);
        return phdr;
    }
};

// Syscalls
pub const syscall = root.syscall;
pub fn sysExit(_: []const usize) syscall.Result {
    log.debug(@src(), "exit", .{});
    // unreachable;
    return .success;
}
