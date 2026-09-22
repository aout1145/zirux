const std = @import("std");
const root = @import("root");
const hal = root.hal;

const init_cpu = 0;
pub fn init() !void {
    if (hal.cpu.getLocalCpuId() == init_cpu) {
        hal.syscall.setDispatcher(dispatch);
    }
}

pub const Handler = *const fn (args: []const usize) Result;
pub const Result = enum(usize) {
    success = 0,
    not_implemented = 1,
    out_of_memory = 2,
    bad_address = 3,
    file_not_found = 4,
    operation_not_supported = 5,
    invalid_argument = 6,
    bad_file_id = 7,
    no_space_left = 8,
};

fn checkAddrAvailable(addr: hal.page.VirtAddr, len: usize) bool {
    if (addr < hal.page.user_base or addr + len > hal.page.user_base + hal.page.user_size) {
        return false;
    }

    const addr_start = std.mem.alignBackward(hal.page.PhysAddr, addr, hal.page.page_size);
    const addr_end = std.mem.alignForward(hal.page.PhysAddr, addr + len, hal.page.page_size);
    const pages_num = @divExact(addr_end - addr_start, hal.page.page_size);
    for (0..pages_num) |i| {
        const proc = root.sched.process.getLocalCurrentProcess();
        const lock_flag = proc.lock.lock();
        defer proc.lock.unlock(lock_flag);

        const pt = proc.page_table;
        if (pt.query(addr_start + i * hal.page.page_size) == null) {
            return false;
        }
    }

    return true;
}
pub inline fn getUserPtr(T: type, addr: hal.page.VirtAddr) ?*T {
    if (checkAddrAvailable(addr, @sizeOf(T))) {
        return @ptrFromInt(addr);
    } else {
        return null;
    }
}
pub inline fn getUserSlice(T: type, addr: hal.page.VirtAddr, len: usize) ?[]T {
    if (checkAddrAvailable(addr, len * @sizeOf(T))) {
        const ptr: [*]T = @ptrFromInt(addr);
        return ptr[0..len];
    } else {
        return null;
    }
}
pub inline fn getUserInt(T: type, int: usize) ?T {
    if (int <= std.math.maxInt(T)) {
        return @intCast(int);
    } else {
        return null;
    }
}

var syscalls = [_]Handler{
    root.sched.process.sysExit, // 0
    root.sched.process.sysMemMap, // 1
    root.sched.process.sysOpen, // 2
    root.sched.process.sysRead, // 3
    root.sched.process.sysWrite, // 4
};
fn dispatch(number: usize, args: []const usize) usize {
    return if (number <= syscalls.len)
        @intFromEnum(syscalls[number](args))
    else
        @intFromEnum(Result.not_implemented);
}
