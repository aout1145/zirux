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

pub fn init(gs_base: u64) void {
    // Initialize GS.Base
    var cr4 = arch.@"asm".readCtrlRegister(arch.@"asm".registers.Cr4, "cr4");
    cr4.fsgsbase = true;
    arch.@"asm".writeCtrlRegister("cr4", cr4);
    arch.@"asm".registers.GsBase.write(.{ .gs_base = gs_base });
}

pub inline fn getLcpuId() u32 {
    return asm volatile (
        \\mov $0x0B, %eax
        \\xor %ecx, %ecx
        \\cpuid
        : [_] "={edx}" (-> u32),
    );
}

pub inline fn ptr(T: type, pcp: *T) *T {
    assert(arch.sched.getPreemptCount() != 0);
    return @ptrFromInt(@intFromPtr(pcp) + arch.@"asm".registers.GsBase.read().gs_base);
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
