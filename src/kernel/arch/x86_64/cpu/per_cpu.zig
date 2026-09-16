const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;

pub const section = ".per_cpu";

extern const __kernel_per_cpu_start: [*]const u8;
extern const __kernel_per_cpu_end: [*]const u8;

pub fn allocate(gpa: std.mem.Allocator) !u64 {
    // Allocator memory for per-cpu area
    const len = @intFromPtr(&__kernel_per_cpu_end) - @intFromPtr(&__kernel_per_cpu_start);
    const mem = try gpa.alignedAlloc(u8, .fromByteUnits(arch.mem.page.page_size), len);
    const init_ptr: [*]const u8 = @ptrCast(&__kernel_per_cpu_start);
    @memcpy(mem, init_ptr[0..len]);
    return @intFromPtr(mem.ptr) - (@intFromPtr(&__kernel_per_cpu_start) - arch.mem.kernel_base);
}

pub inline fn init(gs_base: u64) void {
    // Initialize GS.Base
    arch.@"asm".writeMsr(arch.@"asm".registers.GsBase.msr, gs_base);
}

var gs_bases: std.array_list.Aligned(u64, .fromByteUnits(arch.cpu.cache_line)) = .empty;
var gs_bases_initalized: bool linksection(section) = false;
pub fn initFull() !void {
    const lcpu_id = getLocalCpuId();
    if (gs_bases.items.len <= lcpu_id) {
        try gs_bases.resize(root.mem.general_allocator, lcpu_id + 1);
    }
    gs_bases.items[lcpu_id] = arch.@"asm".readMsr(arch.@"asm".registers.GsBase.msr);
    write(bool, &gs_bases_initalized, true);
}

inline fn getLcpuId() u32 {
    return asm volatile (
        \\mov $0x0B, %eax
        \\xor %ecx, %ecx
        \\cpuid
        : [_] "={edx}" (-> u32),
        :
        : .{ .rax = true, .rbx = true, .rcx = true, .rdx = true });
}
var cpu_id: u64 linksection(section) = std.math.maxInt(u64);
pub inline fn getLocalCpuId() root.hal.cpu.CpuId {
    var local_cpu_id = read(u64, &cpu_id);
    if (local_cpu_id == std.math.maxInt(u64) or !read(bool, &gs_bases_initalized)) {
        @branchHint(.cold);
        local_cpu_id = getLcpuId();
        write(u64, &cpu_id, local_cpu_id);
    }
    return @intCast(local_cpu_id);
}

pub inline fn ptr(T: type, pcp: *T) *T {
    if (!read(bool, &gs_bases_initalized)) {
        @branchHint(.cold);
        return @ptrFromInt(@intFromPtr(pcp) + arch.@"asm".readMsr(arch.@"asm".registers.GsBase.msr));
    } else {
        @branchHint(.likely);
        return @ptrFromInt(@intFromPtr(pcp) + gs_bases.items[root.hal.cpu.getLocalCpuId()]);
    }
}

pub inline fn read(T: type, pcp: *const T) T {
    return asm volatile (
        \\mov %%gs:(%[pcp]), %[val]
        : [val] "=r" (-> T),
        : [pcp] "r" (pcp),
        : .{ .memory = true });
}

pub inline fn write(T: type, pcp: *T, val: T) void {
    asm volatile (
        \\mov %[val], %%gs:(%[pcp])
        :
        : [pcp] "r" (pcp),
          [val] "r" (val),
        : .{ .memory = true });
}

pub inline fn add(T: type, pcp: *T, val: T) void {
    asm volatile (
        \\add %[val], %%gs:(%[pcp])
        :
        : [pcp] "r" (pcp),
          [val] "r" (val),
        : .{ .memory = true });
}

pub inline fn sub(T: type, pcp: *T, val: T) void {
    asm volatile (
        \\sub %[val], %%gs:(%[pcp])
        :
        : [pcp] "r" (pcp),
          [val] "r" (val),
        : .{ .memory = true });
}
