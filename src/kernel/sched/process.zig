const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const hal = root.hal;
const utils = root.utils;
const sync = root.sync;
const mem = root.mem;
const allocator = mem.general_allocator;

const thread = @import("thread.zig");

pub const ProcessId = u32;
pub const Process = struct {
    proc_name: [8]u8,
    proc_id: ProcessId,

    page_table: mem.page_table.PageTablePtr,
    thrd_ids: std.ArrayList(thread.ThreadId),
};

var initialized: bool = false;
var process_lock: sync.SpinLockIrq = .unlocked;
var processes: utils.IdAllocator(ProcessId, Process) = .empty;

pub fn init() !void {
    const lock_flag = process_lock.lock();
    defer process_lock.unlock(lock_flag);

    if (!initialized) {
        // Create IDLE(0) process
        const idle_pid = try processes.alloc(allocator);
        assert(idle_pid == 0);
        const idle_proc = processes.get(idle_pid).?;
        idle_proc.* = .{
            .proc_name = "IDLE".* ++ .{0} ** 4,
            .proc_id = idle_pid,
            .page_table = undefined, // TODO: clone
            .thrd_ids = .empty,
        };
        try idle_proc.thrd_ids.append(allocator, try thread.init());

        initialized = true;
    }
}
