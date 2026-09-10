const std = @import("std");
const root = @import("root");
const arch = root.arch.target;

pub const cache_line = arch.cpu.cache_line;

pub inline fn endlessHalt() noreturn {
    arch.cpu.endlessHalt();
    unreachable;
}

pub const per_cpu_section = arch.cpu.per_cpu.section;
pub const this_cpu = struct {
    const per_cpu = arch.cpu.per_cpu;
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

pub const Cpu = struct {
    type: enum {
        bsp,
        ap,
    },
    id: u32,
};
pub inline fn getCpuList() []const Cpu {
    return arch.cpu.smp.cpu_list.items;
}
pub inline fn getLocalCpuId() u32 {
    return arch.cpu.per_cpu.getLcpuId();
}
