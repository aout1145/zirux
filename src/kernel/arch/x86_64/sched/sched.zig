const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;

var preempt_count: u32 linksection(arch.cpu.per_cpu.section) = 1;
pub inline fn getPreemptCount() u32 {
    return arch.cpu.per_cpu.read(u32, &preempt_count);
}
pub inline fn preemptDisable() void {
    arch.cpu.per_cpu.add(u32, &preempt_count, 1);
}
pub inline fn preemptEnable() void {
    assert(getPreemptCount() != 0);
    arch.cpu.per_cpu.sub(u32, &preempt_count, 1);
}

var __save_sp: ?*u64 linksection(arch.cpu.per_cpu.section) = null;
var __next_sp: u64 linksection(arch.cpu.per_cpu.section) = 0;
pub inline fn switchTo(save_sp: *u64, next_sp: u64) void {
    assert(__save_sp == null);
    assert(__next_sp == 0);
    __save_sp = save_sp;
    __next_sp = next_sp;
}
export fn spSwitch() callconv(.naked) void {
    asm volatile (
        \\cmpq $0, %%gs:(%[next_sp])
        \\je 1f
        \\cmpl $0, %%gs:(%[preempt_count])
        \\je 2f
        \\movq %%gs:(%[save_sp]), %%rax
        \\movq %%rsp, (%%rax)
        \\movq %%gs:(%[next_sp]), %%rsp
        \\2:
        \\movq $0, %%gs:(%[save_sp])
        \\movq $0, %%gs:(%[next_sp])
        \\1:
        \\ret
        :
        : [next_sp] "r" (&__next_sp),
          [save_sp] "r" (&__save_sp),
          [preempt_count] "r" (&preempt_count),
        : .{
          .memory = true,
          .rsp = true,
          .rax = true,
        });
}
