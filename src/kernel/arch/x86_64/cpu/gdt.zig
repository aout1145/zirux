const std = @import("std");
const root = @import("root");
const assert = std.debug.assert;
const log = root.debug.log;
const arch = root.arch.x86_64;
const per_cpu = arch.cpu.per_cpu;

pub fn init() void {
    // Refresh %gs will clear GS.Base, so we save it first.
    const gs_base = arch.@"asm".readMsr(arch.@"asm".registers.GsBase.msr);

    const local_gdtr = per_cpu.ptr(GdtRegister, &gdtr);
    const local_gdt = per_cpu.ptr([max_num_gdt]SegmentDescriptor, &gdt);
    const local_tss = per_cpu.ptr(TaskStateSegment, &tss);

    local_gdtr.base = @intFromPtr(local_gdt);
    local_gdt[kernel_cs_index] = SegmentDescriptor.init(
        0,
        std.math.maxInt(u20),
        0x9A,
        0xA,
    );
    local_gdt[kernel_ds_index] = SegmentDescriptor.init(
        0,
        std.math.maxInt(u20),
        0x92,
        0xC,
    );
    local_gdt[user_ds_index] = SegmentDescriptor.init(
        0,
        std.math.maxInt(u20),
        0xF2,
        0xC,
    );
    local_gdt[user_cs_index] = SegmentDescriptor.init(
        0,
        std.math.maxInt(u20),
        0xFA,
        0xA,
    );
    // log.debug(@src(), "{x}", .{@intFromPtr(&local_gdt[tss_index])});
    const tss_ptr: *align(8) LongSegmentDescriptor = @ptrCast(@alignCast(&local_gdt[tss_index]));
    tss_ptr.* = LongSegmentDescriptor.init(
        @intFromPtr(local_tss),
        @sizeOf(TaskStateSegment) - 1,
        0x89,
        0x0,
    );
    lgdt(@intFromPtr(local_gdtr));
    loadDs(kernel_ds_selector);
    loadCs(kernel_cs_selector);
    loadTss(0, tss_index);

    // Restore GS.Base
    arch.@"asm".writeMsr(arch.@"asm".registers.GsBase.msr, gs_base);
}

const SegmentDescriptor = packed struct(u64) {
    limit_low: u16,
    base_low: u24,
    access_byte: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,

    pub fn initNull() SegmentDescriptor {
        return @bitCast(@as(u64, 0));
    }
    pub fn init(
        base: u32,
        limit: u20,
        access_byte: u8,
        flags: u4,
    ) SegmentDescriptor {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .access_byte = access_byte,
            .flags = flags,
            .limit_high = @truncate(limit >> 16),
            .base_high = @truncate(base >> 24),
        };
    }
};
const SegmentSelector = packed struct(u16) {
    /// Requested Privilege Level.
    rpl: u2,
    /// Table Indicator.
    ti: u1 = 0,
    /// Index.
    index: u13,
};
const GdtRegister = packed struct {
    limit: u16,
    base: u64,
};
const max_num_gdt = 0x7;
pub const kernel_cs_index = 0x01;
pub const kernel_cs_selector: SegmentSelector = .{
    .rpl = 0,
    .index = kernel_cs_index,
};
pub const kernel_ds_index = 0x02;
pub const kernel_ds_selector: SegmentSelector = .{
    .rpl = 0,
    .index = kernel_ds_index,
};
pub const user_ds_index = 0x03;
pub const user_ds_selector: SegmentSelector = .{
    .rpl = 3,
    .index = user_ds_index,
};
pub const user_cs_index = 0x04;
pub const user_cs_selector: SegmentSelector = .{
    .rpl = 3,
    .index = user_cs_index,
};
comptime {
    // Check for SYSCALL/SYSRET
    const kernel_cs: u16 = @bitCast(kernel_cs_selector);
    const kernel_ds: u16 = @bitCast(kernel_ds_selector);
    const user_cs: u16 = @bitCast(user_cs_selector);
    const user_ds: u16 = @bitCast(user_ds_selector);
    assert(kernel_ds == kernel_cs + 8);
    assert(user_cs == user_ds + 8);
}
var gdt: [max_num_gdt]SegmentDescriptor align(16) linksection(arch.cpu.per_cpu.section) = [_]SegmentDescriptor{
    SegmentDescriptor.initNull(),
} ** max_num_gdt;
var gdtr: GdtRegister linksection(arch.cpu.per_cpu.section) = .{
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
    .base = undefined,
};
fn lgdt(val: u64) void {
    asm volatile (
        \\lgdt (%[gdtr])
        :
        : [gdtr] "r" (val),
    );
}
fn loadCs(comptime selector: SegmentSelector) void {
    asm volatile (
        \\
        // Push CS
        \\mov %[cs], %%rax
        \\push %%rax
        // Push RIP
        \\leaq next(%%rip), %%rax
        \\pushq %%rax
        \\lretq
        \\next:
        \\
        :
        : [cs] "n" (@as(u16, @bitCast(selector))),
    );
}
fn loadDs(comptime selector: SegmentSelector) void {
    asm volatile (
        \\mov %[ds], %di
        \\mov %%di, %%ds
        \\mov %%di, %%es
        \\mov %%di, %%fs
        \\mov %%di, %%gs
        \\mov %%di, %%ss
        :
        : [ds] "n" (@as(u16, @bitCast(selector))),
        : .{ .di = true });
}

pub const TaskStateSegment = packed struct {
    _reserved0: u32 = 0,
    rsp0: u64,
    rsp1: u64,
    rsp2: u64,
    _reserved1: u64 = 0,
    ist1: u64,
    ist2: u64,
    ist3: u64,
    ist4: u64,
    ist5: u64,
    ist6: u64,
    ist7: u64,
    _reserved2: u64 = 0,
    _reserved3: u16 = 0,
    iopb: u16,
};
const LongSegmentDescriptor = packed struct(u128) {
    limit_low: u16,
    base_low: u24,
    access_byte: u8,
    limit_high: u4,
    flags: u4,
    base_high: u40,
    _reserved: u32 = 0,

    pub fn init(
        base: u64,
        limit: u20,
        access_byte: u8,
        flags: u4,
    ) LongSegmentDescriptor {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .access_byte = access_byte,
            .flags = flags,
            .limit_high = @truncate(limit >> 16),
            .base_high = @truncate(base >> 24),
        };
    }
};
pub const tss_index = 0x05;
pub var tss: TaskStateSegment linksection(arch.cpu.per_cpu.section) = std.mem.zeroes(TaskStateSegment);
fn loadTss(comptime rpl: u2, comptime index: u13) void {
    asm volatile (
        \\mov %[kernel_tss], %%di
        \\ltr %%di
        :
        : [kernel_tss] "n" (@as(u16, @bitCast(SegmentSelector{
            .rpl = rpl,
            .index = index,
          }))),
        : .{ .di = true });
}
