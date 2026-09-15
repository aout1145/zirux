const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const hal = root.hal;
const utils = root.utils;
const sync = root.sync;
const time = root.time;
const allocator = root.mem.general_allocator;
// TODO: use vmap to improve security
const vmap_allocator = root.mem.general_allocator;

const process = @import("process.zig");

pub const ThreadId = u32;
pub const Thread = struct {
    _refcount: u32,

    cpu_id: ?hal.cpu.CpuId,
    thrd_id: ThreadId,
    proc: *process.Process,

    sp: hal.context.StackPointer,
    stack: []u8,

    priority: u8,

    pub inline fn ref(self: *Thread) void {
        return sync.ref(u32, &self._refcount);
    }
    pub inline fn unref(self: *Thread) bool {
        if (sync.unref(u32, &self._refcount)) {
            const lock_flag = thread_lock.lock();
            defer thread_lock.unlock(lock_flag);
            self.proc.unref();
            vmap_allocator.free(self.stack);
            threads.free(allocator, self.thrd_id);
        }
    }
};
pub const kernel_stack_size = 2 * hal.page.page_size;
pub const priority = struct {
    pub const realtime = 0;
    pub const high = 1;
    pub const normal = 2;
};

var thread_lock: sync.SpinLockIrq = .unlocked;
var threads: utils.IdAllocator(ThreadId, Thread) = .empty;

/// Return idle tid of this cpu
pub fn init(idle_proc: *process.Process) !ThreadId {
    const local_cpu_id = hal.cpu.getLocalCpuId();

    // Initialize sched_queue
    const lock_flag = thread_lock.lock();
    defer thread_lock.unlock(lock_flag);

    if (sched_queue.items.len <= local_cpu_id)
        try sched_queue.resize(allocator, local_cpu_id + 1);
    sched_queue.items[local_cpu_id] = .empty;

    // Create idle thread
    const idle_tid = try threads.alloc(allocator);
    const idle_thrd = threads.get(idle_tid).?;
    idle_thrd.* = .{
        ._refcount = 1,
        .cpu_id = hal.cpu.getLocalCpuId(),
        .thrd_id = idle_tid,
        .proc = idle_proc,
        .sp = undefined,
        .stack = undefined,
        .priority = 0,
    };
    const idle_sched_elem: ScheduleElem = .{
        .thrd = idle_thrd,
        .vcputime = std.math.maxInt(u64),
    };
    const local_sched_queue = &sched_queue.items[local_cpu_id];
    try local_sched_queue.push(allocator, idle_sched_elem);
    const local_current_elem = hal.cpu.this_cpu.ptr(ScheduleElem, &current_elem);
    local_current_elem.* = idle_sched_elem;

    return idle_tid;
}

pub const Options = struct {
    priority: u8 = priority.normal,
};
pub fn createThread(proc: *process.Process, entry: hal.page.VirtAddr, options: Options) !ThreadId {
    const lock_flag = thread_lock.lock();
    defer thread_lock.unlock(lock_flag);

    const stack = try vmap_allocator.alignedAlloc(u8, .fromByteUnits(hal.page.page_size), kernel_stack_size);
    errdefer vmap_allocator.free(stack);

    const tid = try threads.alloc(allocator);
    const thrd = threads.get(tid).?;
    thrd.* = .{
        ._refcount = 1,
        .cpu_id = null,
        .thrd_id = tid,
        .proc = proc,
        .sp = hal.context.init(stack, entry, true),
        .stack = stack,
        .priority = options.priority,
    };
    proc.ref();
    errdefer proc.unref();
    // log.debug(@src(), "created thread {}", .{tid});
    try add(thrd);

    return tid;
}

// Schedule algorithm
fn lessThan(_: void, a: ScheduleElem, b: ScheduleElem) std.math.Order {
    return std.math.order(a.vcputime, b.vcputime);
}
const ScheduleElem = struct {
    thrd: *Thread,
    vcputime: u64,
};
const ScheduleQueue = std.PriorityQueue(ScheduleElem, void, lessThan);

var sched_queue_lock: sync.SpinLockIrq = .unlocked;
var sched_queue: std.ArrayList(ScheduleQueue) = .empty;
var sched_time: u64 linksection(hal.cpu.per_cpu_section) = 0;
var current_elem: ScheduleElem linksection(hal.cpu.per_cpu_section) = undefined;

inline fn add(thrd: *Thread) !void {
    const lock_flag = sched_queue_lock.lock();
    defer sched_queue_lock.unlock(lock_flag);

    const cpu_id = thrd.cpu_id orelse blk: {
        var min_cpu_id: hal.cpu.CpuId = 0;
        var min_count: usize = std.math.maxInt(usize);
        for (sched_queue.items, 0..) |cpu_sched_queue, i| {
            if (min_count > cpu_sched_queue.count()) {
                min_cpu_id = @intCast(i);
                min_count = cpu_sched_queue.count();
            }
        }
        break :blk min_cpu_id;
    };

    const cpu_sched_queue = &sched_queue.items[cpu_id];
    var iter = cpu_sched_queue.iterator();
    var total_vcputime: u64 = 0;
    var total_count: usize = 0;
    while (iter.next()) |elem| {
        if (elem.thrd.priority == 0) continue;
        total_vcputime += elem.vcputime;
        total_count += 1;
    }
    const init_vcputime = if (total_vcputime == 0) 0 else total_vcputime / total_count;
    log.debug(@src(), "add thread {} on cpu#{}, vcputime: {}", .{ thrd.thrd_id, cpu_id, init_vcputime });
    try cpu_sched_queue.push(allocator, .{
        .thrd = thrd,
        .vcputime = init_vcputime,
    });
}

pub fn schedule() void {
    const local_cpu_id = hal.cpu.getLocalCpuId();
    const lock_flag = sched_queue_lock.lock();
    const local_sched_queue = &sched_queue.items[local_cpu_id];

    const current_time = time.jiffies.getClock();
    var local_current_elem = hal.cpu.this_cpu.ptr(ScheduleElem, &current_elem);
    const original_current_elem = local_current_elem.*;
    // Update current_elem's vcputime
    local_current_elem.vcputime += (current_time - hal.cpu.this_cpu.read(u64, &sched_time)) * local_current_elem.thrd.priority;
    hal.cpu.this_cpu.write(u64, &sched_time, current_time);
    local_sched_queue.update(original_current_elem, local_current_elem.*) catch unreachable;
    // log.debug(@src(), "thread {}: new vcputime {}", .{ local_current_elem.thrd.thrd_id, local_current_elem.vcputime });
    // Get next sched_elem
    const next_elem = local_sched_queue.peek().?;
    sched_queue_lock.unlock(lock_flag);

    if (local_current_elem.thrd.thrd_id != next_elem.thrd.thrd_id) {
        log.debug(@src(), "switch to tid {}", .{next_elem.thrd.thrd_id});
        hal.sched.contextSwitch(&local_current_elem.thrd.sp, next_elem.thrd.stack, next_elem.thrd.sp);
        if (local_current_elem.thrd.proc.proc_id != next_elem.thrd.proc.proc_id) {
            log.debug(@src(), "switch to pid {}", .{next_elem.thrd.proc.proc_id});
            const new_page_table = next_elem.thrd.proc.page_table;
            hal.page.writePagingBase(@intFromPtr(new_page_table.global_table) - hal.page.direct_map_base);
        }
        local_current_elem.* = next_elem;
    }
}
