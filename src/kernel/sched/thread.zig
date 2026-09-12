const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const hal = root.hal;
const utils = root.utils;
const sync = root.sync;
const allocator = root.mem.general_allocator;

const process = @import("process.zig");

pub const ThreadId = u32;
pub const Thread = struct {
    cpu_id: hal.cpu.CpuId,
    thrd_id: ThreadId,
    proc_id: process.ProcessId,

    sp: hal.context.StackPointer,
    stack: []u8,

    priority: u8,
    vcputime: u64,
};

var thread_lock: sync.SpinLockIrq = .unlocked;
var threads: utils.IdAllocator(ThreadId, Thread) = .empty;

/// Return idle tid of this cpu
pub fn init() !ThreadId {
    const lock_flag = thread_lock.lock();
    defer thread_lock.unlock(lock_flag);

    const idle_tid = try threads.alloc(allocator);
    const idle_thrd = threads.get(idle_tid).?;
    idle_thrd.* = .{
        .cpu_id = hal.cpu.getLocalCpuId(),
        .thrd_id = idle_tid,
        .proc_id = 0,
        .sp = undefined,
        .stack = undefined,
        .priority = 0,
        .vcputime = std.math.maxInt(u64),
    };
    try add(idle_tid, idle_thrd.vcputime);

    return idle_tid;
}

// Schedule algorithm
const ScheduleElem = struct {
    tid: u64,
    vcputime: u64,
};
fn lessThan(_: void, a: ScheduleElem, b: ScheduleElem) std.math.Order {
    return std.math.order(a.vcputime, b.vcputime);
}
const ScheduleQueue = std.PriorityQueue(ScheduleElem, void, lessThan);
var sched_queue: ScheduleQueue linksection(hal.cpu.per_cpu_section) = .empty;
var current_tid: ThreadId linksection(hal.cpu.per_cpu_section) = undefined;

// NOTE: should disable preempt
pub inline fn add(tid: ThreadId, vcputime: u64) !void {
    const local_sched_queue = hal.cpu.this_cpu.ptr(ScheduleQueue, &sched_queue);
    try local_sched_queue.push(allocator, .{
        .tid = tid,
        .vcputime = vcputime,
    });
}

pub fn yield() void {}
pub fn schedule() void {}
