const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

pub const ExceptionType = enum {
    unknown,
    /// Unrecoverable Errors
    abort,
    /// Divide by Zero
    division_error,
    /// Page Fault
    page_fault,
};
pub const Exception = union(ExceptionType) {
    unknown: void,
    abort: void,
    division_error: void,
    page_fault: PageFault,
    pub const PageFault = struct {
        /// The virtual address that caused exception
        virt_addr: hal.page.VirtAddr,
    };
};

pub const IrqNumber = u32;
pub inline fn getIrq() IrqNumber {}
/// Disable interrupt and save flags
pub inline fn irqSave() u8 {
    return arch.intr.irqSave();
}
/// Ensable interrupt and restore flags
pub inline fn irqRestore(flag: u8) void {
    arch.intr.irqRestore(flag);
}

/// Return 0 when preempt enabled
pub inline fn getPreemptCount() u32 {
    return arch.intr.getPreemptCount();
}
pub inline fn preemptDisable() void {
    arch.intr.preemptDisable();
}
pub inline fn preemptEnable() void {
    arch.intr.preemptEnable();
}
