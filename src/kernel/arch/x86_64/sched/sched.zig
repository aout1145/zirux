const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;

export var save_sp: ?*u64 linksection(arch.cpu.per_cpu.section) = null;
export var next_sp: u64 linksection(arch.cpu.per_cpu.section) = 0;
pub inline fn contextSwitch(arg_save_sp: *u64, stack: []u8, arg_next_sp: u64) void {
    assert(arch.cpu.per_cpu.read(?*u64, &save_sp) == null);
    assert(arch.cpu.per_cpu.read(u64, &next_sp) == 0);
    arch.cpu.per_cpu.write(?*u64, &save_sp, arg_save_sp);
    arch.cpu.per_cpu.write(u64, &next_sp, arg_next_sp);
    // Update tss.rsp0
    const tss = arch.cpu.per_cpu.ptr(arch.cpu.gdt.TaskStateSegment, &arch.cpu.gdt.tss);
    tss.rsp0 = @intFromPtr(stack.ptr) + stack.len;
    // Update syscall.kernel_rsp
    arch.cpu.per_cpu.write(u64, &arch.syscall.kernel_rsp, @intFromPtr(stack.ptr) + stack.len);
}
export fn spSwitch() callconv(.naked) void {
    asm volatile (
        \\cmpq $0, %%gs:next_sp
        \\je 1f
        \\cmpl $0, %%gs:preempt_count
        \\je 2f
        \\movq %%gs:save_sp, %%rax
        \\movq %%rsp, (%%rax)
        \\movq %%gs:next_sp, %%rsp
        \\2:
        \\movq $0, %%gs:save_sp
        \\movq $0, %%gs:next_sp
        \\1:
    );
}
