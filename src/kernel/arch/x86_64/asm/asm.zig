pub const cpuid = @import("cpuid.zig");
pub const registers = @import("registers.zig");

pub inline fn halt() void {
    asm volatile ("hlt");
}

pub inline fn pause() void {
    asm volatile ("pause");
}

pub inline fn readRegister(comptime reg: []const u8) u64 {
    return asm volatile ("mov %%" ++ reg ++ ", %[val]"
        : [val] "=r" (-> u64),
    );
}
pub inline fn writeRegister(comptime reg: []const u8, val: u64) void {
    asm volatile ("mov %[val], %%" ++ reg
        :
        : [val] "r" (val),
    );
}
pub inline fn readCtrlRegister(T: type, comptime reg: []const u8) T {
    return @bitCast(readRegister(reg));
}
pub inline fn writeCtrlRegister(comptime reg: []const u8, val: anytype) void {
    writeRegister(reg, @bitCast(val));
}
pub inline fn readRflags() registers.Rflags {
    return @bitCast(asm volatile (
        \\pushfq
        \\popq %[val]
        : [val] "=r" (-> u64),
    ));
}
pub inline fn writeRflags(val: registers.Rflags) void {
    asm volatile (
        \\pushq %[val]
        \\popfq
        :
        : [val] "r" (val),
    );
}

pub inline fn readMsr(msr: u32) u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdmsr"
        : [_] "={rax}" (lo),
          [_] "={rdx}" (hi),
        : [_] "{rcx}" (msr),
    );
    return lo | (@as(u64, hi) << 32);
}
pub inline fn writeMsr(msr: u32, val: u64) void {
    asm volatile ("wrmsr"
        :
        : [_] "{rax}" (@as(u32, @truncate(val))),
          [_] "{rdx}" (@as(u32, @truncate(val >> 32))),
          [_] "{rcx}" (msr),
    );
}
pub inline fn readCtrlMsr(T: type, msr: u32) T {
    return @bitCast(readMsr(msr));
}
pub inline fn writeCtrlMsr(msr: u32, val: anytype) void {
    writeMsr(msr, @bitCast(val));
}
