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

    thrd_id: ThreadId,
    proc: *process.Process,

    sp: hal.context.StackPointer,
    stack: []u8,

    is_cpu_attached: std.atomic.Value(bool),
    attached_cpu_id: std.atomic.Value(hal.cpu.CpuId),

    priority: std.atomic.Value(u8),

    pub inline fn ref(self: *Thread) void {
        return sync.ref(u32, &self._refcount);
    }
    pub inline fn unref(self: *Thread) void {
        if (sync.unref(u32, &self._refcount)) {
            self.proc.unref();
            vmap_allocator.free(self.stack);
            threads.free(allocator, self.thrd_id) catch {};
        }
    }
};
pub const kernel_stack_size = 2 * hal.page.page_size;
pub const priority = struct {
    pub const realtime = 0;
    pub const high = 1;
    pub const normal = 2;
    pub const idle = 255;
};

var threads: utils.IdAllocator(ThreadId, Thread) = .empty;

var init_lock: sync.SpinLockIrq = .unlocked;
/// Return idle tid of this cpu
pub fn init(idle_proc: *process.Process) !ThreadId {
    const local_cpu_id = hal.cpu.getLocalCpuId();

    { // Initialize sched_queue
        const lock_flag = init_lock.lock();
        defer init_lock.unlock(lock_flag);

        if (sched_queue.items.len <= local_cpu_id)
            try sched_queue.resize(allocator, local_cpu_id + 1);
        sched_queue.items[local_cpu_id] = .{ .lock = .unlocked, .queue = .empty };
    }

    // Create idle thread
    idle_proc.ref();
    const idle_tid = try threads.alloc(allocator, .{
        ._refcount = 1,
        .thrd_id = undefined,
        .proc = idle_proc,
        .sp = undefined,
        .stack = &.{},
        .is_cpu_attached = .init(true),
        .attached_cpu_id = .init(hal.cpu.getLocalCpuId()),
        .priority = .init(0),
    }, "thrd_id");
    // The idle thread is never freed, so the lock can be released right away.
    var locked_idle_thrd = threads.get(idle_tid);
    const idle_thrd = locked_idle_thrd.value orelse unreachable;
    locked_idle_thrd.unlock();

    const idle_sched_elem: ScheduleElem = .{
        .thrd = idle_thrd,
        .vcputime = std.math.maxInt(u64),
    };

    { // Add idle thread to schedule queue
        const local_sched_queue = &sched_queue.items[local_cpu_id];
        const lock_flag = local_sched_queue.lock.lock();
        defer local_sched_queue.lock.unlock(lock_flag);

        idle_thrd.ref();
        try local_sched_queue.queue.push(allocator, idle_sched_elem);
    }

    // Set idle thread as the current
    const local_current_elem = hal.cpu.this_cpu.ptr(ScheduleElem, &current_elem);
    idle_thrd.ref();
    local_current_elem.* = idle_sched_elem;

    return idle_tid;
}

pub const Options = struct {
    priority: u8 = priority.normal,
};
pub fn createThread(proc: *process.Process, entry: hal.page.VirtAddr, options: Options) !ThreadId {
    const stack = try vmap_allocator.alignedAlloc(u8, .fromByteUnits(hal.page.page_size), kernel_stack_size);
    errdefer vmap_allocator.free(stack);

    proc.ref();
    errdefer proc.unref();

    const tid = try threads.alloc(allocator, .{
        ._refcount = 1,
        .thrd_id = undefined,
        .proc = proc,
        .sp = hal.context.init(stack, entry, true),
        .stack = stack,
        .is_cpu_attached = .init(false),
        .attached_cpu_id = .init(undefined),
        .priority = .init(options.priority),
    }, "thrd_id");
    errdefer threads.free(allocator, tid) catch {};

    // log.debug(@src(), "created thread {}", .{tid});
    // `tid` is not published yet and `add` only takes a reference, so holding
    // the allocator lock across it is unnecessary (and would risk lock-order
    // inversion with the scheduler queue lock).
    var locked_thrd = threads.get(tid);
    const thrd = locked_thrd.value orelse unreachable;
    locked_thrd.unlock();
    try add(thrd);

    return tid;
}

// Schedule algorithm
const ScheduleElem = struct {
    thrd: *Thread,
    vcputime: u64,
};
fn lessThan(_: void, a: ScheduleElem, b: ScheduleElem) std.math.Order {
    return std.math.order(a.vcputime, b.vcputime);
}
const ScheduleQueue = struct {
    lock: sync.SpinLockIrq,
    queue: std.PriorityQueue(ScheduleElem, void, lessThan),
};
var sched_queue: std.array_list.Aligned(ScheduleQueue, .fromByteUnits(hal.cpu.cache_line)) = .empty;
var sched_time: u64 linksection(hal.cpu.per_cpu_section) = 0;
var current_elem: ScheduleElem linksection(hal.cpu.per_cpu_section) = undefined;

fn add(thrd: *Thread) !void {
    const cpu_id = if (thrd.is_cpu_attached.load(.acquire))
        thrd.attached_cpu_id.load(.acquire)
    else blk: {
        var min_cpu_id: hal.cpu.CpuId = 0;
        var min_count: usize = std.math.maxInt(usize);
        for (sched_queue.items, 0..) |*cpu_sched_queue, i| {
            const lock_flag = cpu_sched_queue.lock.lock();
            defer cpu_sched_queue.lock.unlock(lock_flag);

            if (min_count > cpu_sched_queue.queue.count()) {
                min_cpu_id = @intCast(i);
                min_count = cpu_sched_queue.queue.count();
            }
        }
        break :blk min_cpu_id;
    };

    const cpu_sched_queue = &sched_queue.items[cpu_id];
    const lock_flag = cpu_sched_queue.lock.lock();
    defer cpu_sched_queue.lock.unlock(lock_flag);

    const vcputime = if (thrd.priority.load(.acquire) == priority.realtime) 0 else blk: {
        var iter = cpu_sched_queue.queue.iterator();
        var total_vcputime: u64 = 0;
        var total_count: usize = 0;
        while (iter.next()) |elem| {
            if (elem.thrd.priority.load(.acquire) == 0) continue;
            total_vcputime += elem.vcputime;
            total_count += 1;
        }
        break :blk if (total_vcputime == 0) 0 else total_vcputime / total_count;
    };

    // log.debug(@src(), "add thread {} on cpu#{}, vcputime: {}", .{ thrd.thrd_id, cpu_id, vcputime });
    try cpu_sched_queue.queue.push(allocator, .{
        .thrd = thrd,
        .vcputime = vcputime,
    });
    thrd.ref();
}

var pending_unref: ?*Thread linksection(hal.cpu.per_cpu_section) = null;
pub fn schedule() void {
    if (hal.cpu.this_cpu.read(?*Thread, &pending_unref)) |thrd| {
        hal.cpu.this_cpu.write(?*Thread, &pending_unref, null);
        thrd.unref();
    }

    const local_cpu_id = hal.cpu.getLocalCpuId();
    const local_sched_queue = &sched_queue.items[local_cpu_id];
    const lock_flag = local_sched_queue.lock.lock();

    const current_time = time.jiffies.getCount();
    var local_current_elem = hal.cpu.this_cpu.ptr(ScheduleElem, &current_elem);
    const original_current_elem = local_current_elem.*;
    // Update current_elem's vcputime
    const diff_time = (current_time - hal.cpu.this_cpu.read(u64, &sched_time));
    local_current_elem.vcputime += diff_time * local_current_elem.thrd.priority.load(.acquire);
    hal.cpu.this_cpu.write(u64, &sched_time, current_time);
    local_sched_queue.queue.update(original_current_elem, local_current_elem.*) catch {};
    // log.debug(@src(), "thread {}: new vcputime {}", .{ local_current_elem.thrd.thrd_id, local_current_elem.vcputime });
    // Get next sched_elem
    const next_elem = local_sched_queue.queue.peek().?;
    next_elem.thrd.ref();
    local_sched_queue.lock.unlock(lock_flag);

    if (local_current_elem.thrd.thrd_id != next_elem.thrd.thrd_id) {
        if (local_current_elem.thrd.proc.proc_id != next_elem.thrd.proc.proc_id) {
            log.debug(@src(), "switch to pid {}", .{next_elem.thrd.proc.proc_id});
            const new_page_table = next_elem.thrd.proc.page_table;
            hal.page.writePagingBase(@intFromPtr(new_page_table.global_table) - hal.page.direct_map_base);
        }

        log.debug(@src(), "switch to tid {}", .{next_elem.thrd.thrd_id});
        const current_thrd = local_current_elem.thrd;
        local_current_elem.* = next_elem;
        // Unref on next schedule to avoid use-after-free
        hal.cpu.this_cpu.write(?*Thread, &pending_unref, current_thrd);

        hal.context.switchTo(&current_thrd.sp, next_elem.thrd.stack, next_elem.thrd.sp);
    } else {
        next_elem.thrd.unref();
    }
}

pub inline fn getLocalCurrentThread() *Thread {
    return hal.cpu.this_cpu.read(*Thread, &current_elem.thrd);
}

pub fn kill(tid: ThreadId) void {
    // Take an extra reference while holding the lock so that `thrd` stays
    // valid until we are done with it, then release before `unref` (which may
    // free the thread and re-acquire the allocator lock).
    var locked_thrd = threads.get(tid);
    const thrd = locked_thrd.value orelse unreachable;
    thrd.ref();
    locked_thrd.unlock();
    thrd.unref();

    // Remove thread from sched_queue
    for (sched_queue.items) |*cpu_sched_queue| {
        const lock_flag = cpu_sched_queue.lock.lock();
        defer cpu_sched_queue.lock.unlock(lock_flag);

        var iter = cpu_sched_queue.queue.iterator();
        var index: usize = 0;
        while (iter.next()) |elem| : (index += 1) {
            if (elem.thrd.thrd_id == tid) {
                _ = cpu_sched_queue.queue.popIndex(index);
                elem.thrd.unref();
                // If the killed tid is running, reschedule
                // TODO: tell other cpu to reschedule
                const local_current_elem = hal.cpu.this_cpu.ptr(ScheduleElem, &current_elem);
                if (local_current_elem.thrd.thrd_id == tid) {
                    root.sched.setRescheduleFlag();
                }
                return;
            }
        }
    }
}
