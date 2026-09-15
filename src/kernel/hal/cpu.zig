const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const assert = std.debug.assert;

pub const cache_line = arch.cpu.cache_line;

pub inline fn endlessHalt() noreturn {
    arch.cpu.endlessHalt();
    unreachable;
}

pub const per_cpu_section = arch.cpu.per_cpu.section;
pub const this_cpu = struct {
    const per_cpu = arch.cpu.per_cpu;
    pub inline fn ptr(T: type, pcp: *T) *T {
        assert(arch.sched.getPreemptCount() != 0);
        return per_cpu.ptr(T, pcp);
    }
    pub inline fn read(T: type, pcp: *const T) T {
        return per_cpu.read(T, pcp);
    }
    pub inline fn write(T: type, pcp: *T, val: T) void {
        per_cpu.write(T, pcp, val);
    }
    pub inline fn add(T: type, pcp: *T, val: T) void {
        per_cpu.add(T, pcp, val);
    }
    pub inline fn sub(T: type, pcp: *T, val: T) void {
        per_cpu.sub(T, pcp, val);
    }
};

pub const CpuId = u32;
pub const Cpu = struct {
    type: enum {
        bsp,
        ap,
    },
    id: CpuId,
};
pub inline fn getCpuList() []const Cpu {
    return arch.cpu.smp.cpu_list.items;
}
var cpu_id: u64 linksection(per_cpu_section) = std.math.maxInt(u64);
pub inline fn getLocalCpuId() CpuId {
    var local_cpu_id = this_cpu.read(u64, &cpu_id);
    if (local_cpu_id == std.math.maxInt(u64)) {
        @branchHint(.cold);
        local_cpu_id = arch.cpu.per_cpu.getLcpuId();
        this_cpu.write(u64, &cpu_id, local_cpu_id);
    }
    return @intCast(local_cpu_id);
}
