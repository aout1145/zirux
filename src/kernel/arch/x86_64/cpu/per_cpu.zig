const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;

pub const section = ".per_cpu";

extern const __kernel_per_cpu_start: [*]const u8;
extern const __kernel_per_cpu_end: [*]const u8;

pub fn init(gpa: std.mem.Allocator) !void {
    // Allocator memory for per-cpu area
    const len = @intFromPtr(&__kernel_per_cpu_end) - @intFromPtr(&__kernel_per_cpu_start);
    const mem = try gpa.alignedAlloc(u8, .fromByteUnits(arch.mem.page.page_size), len);
    const init_ptr: [*]const u8 = @ptrCast(&__kernel_per_cpu_start);
    @memcpy(mem, init_ptr[0..len]);
    // Initialize GS.Base
    const gs_base = @intFromPtr(mem.ptr) - (@intFromPtr(&__kernel_per_cpu_start) - arch.mem.kernel_base);
    arch.@"asm".writeMsr(arch.@"asm".registers.GsBase.msr, gs_base);
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
