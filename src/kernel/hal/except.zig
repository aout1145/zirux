const std = @import("std");
const root = @import("root");
const arch = root.arch.target;
const hal = root.hal;

pub const ExceptionType = @typeInfo(Exception).@"union".tag_type.?;
pub const Exception = union(enum) {
    unknown: void,
    abort: void,

    /// Debug
    debug: void,
    /// Breakpoint
    breakpoint: void,

    /// Divide by zero
    division_error: void,
    /// Overflow
    overflow: void,

    /// Protection fault
    protection_fault: void,
    /// Illegal instruction
    illegal_instruction: void,
    /// Page fault
    page_fault: struct {
        /// The virtual address that caused exception
        virt_addr: hal.page.VirtAddr,
    },
    /// Alignment check
    alignment_check: void,
    /// Machine check
    machine_check: void,
};

pub const Handler = *const fn (@"type": ExceptionType, ip: hal.page.VirtAddr, ctx: *hal.context.Context) void;
pub inline fn setHandler(@"type": ExceptionType) void {
    _ = @"type";
    @panic("TODO");
}
