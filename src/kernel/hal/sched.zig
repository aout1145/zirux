const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

/// Return 0 when preempt enabled
pub inline fn getPreemptCount() u32 {
    return arch.sched.getPreemptCount();
}
pub inline fn preemptDisable() void {
    arch.sched.preemptDisable();
}
pub inline fn preemptEnable() void {
    arch.sched.preemptEnable();
}

/// Set switch flag that will cause context switch when return from interrupt/syscall
pub inline fn contextSwitch(save_sp: *hal.context.StackPointer, next_kernel_stack: []u8, next_sp: hal.context.StackPointer) void {
    arch.sched.contextSwitch(save_sp, next_kernel_stack, next_sp);
}
