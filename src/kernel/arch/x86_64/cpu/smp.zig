const std = @import("std");
const root = @import("root");
const acpi = root.drivers.acpi;
const arch = root.arch.x86_64;
const allocator = root.mem.general_allocator;
const log = root.debug.log;
const hal = root.hal;
const mem = root.mem;
const ipi = arch.intr.ipi;

pub var cpu_list: std.ArrayList(hal.cpu.Cpu) = .empty;
pub var is_finished: std.atomic.Value(bool) = .init(true);

pub fn init() !void {
    const madt = acpi.xsdt.?.find(acpi.tables.MADT, "APIC").?;
    var iter = madt.iter();
    while (iter.next()) |header| {
        // log.debug(@src(), "{any}", .{header});
        if (header.type != .lapic)
            continue;

        const lapic = header.as(.lapic);
        // log.debug(@src(), "{any}", .{lapic});
        if (lapic.flags.processor_enabled or lapic.flags.online_capable) {}
        try cpu_list.append(allocator, .{
            .type = if (arch.intr.apic.lapicRead(.id) == lapic.apic_id) .bsp else .ap,
            .id = lapic.apic_id,
        });
    }

    const ap_trampoline_len = @intFromPtr(&__kernel_boot_trampoline_end) - @intFromPtr(&__kernel_boot_trampoline_start);
    const ap_trampoline_source_ptr: [*]const u8 = @ptrCast(&__kernel_boot_trampoline_start);
    const ap_trampoline_ptr: [*]u8 = @ptrFromInt(arch.mem.direct_map_base + 0x8000);
    @memcpy(ap_trampoline_ptr[0..ap_trampoline_len], ap_trampoline_source_ptr[0..ap_trampoline_len]);
    for (cpu_list.items) |cpu| {
        if (cpu.type == .bsp) continue;

        const ap_stack_ptr: *u64 = @ptrFromInt(arch.mem.direct_map_base + @intFromPtr(&ap_stack));
        const ap_init_stack = try allocator.alignedAlloc(
            u8,
            .fromByteUnits(arch.mem.page.page_size),
            2 * arch.mem.page.page_size,
        );
        ap_stack_ptr.* = @intFromPtr(ap_init_stack.ptr) + ap_init_stack.len - 0x10;
        const ap_entry_ptr: *u64 = @ptrFromInt(arch.mem.direct_map_base + @intFromPtr(&ap_entry));
        ap_entry_ptr.* = @intFromPtr(&apEntry);

        ap_gsbase = try arch.cpu.per_cpu.allocate(allocator);
        is_finished.store(false, .release);

        ipi.sendRaw(@intCast(cpu.id), 0, .icr_high, .init);
        // TODO: delay 10ms
        ipi.sendRaw(@intCast(cpu.id), 0x8, .icr_high, .sipi);
        // ipi.sendRaw(@intCast(cpu.id), 0x8, .icr_high, .sipi);

        while (!is_finished.load(.acquire)) {
            arch.@"asm".pause();
        }
    }
    // ipi.sendRaw(0, 33, .others, .normal);
}

var ap_gsbase: u64 = 0;
fn apEntry() callconv(.c) noreturn {
    apZigEntry() catch |e| @panic(@errorName(e));
    unreachable;
}
fn apZigEntry() !void {
    arch.cpu.init();
    arch.cpu.per_cpu.init(ap_gsbase);
    arch.cpu.gdt.init();

    arch.mem.page.init();
    var lock_flag: u8 = undefined;
    const pt = mem.page_table.getKernelPageTable(&lock_flag);
    hal.page.writePagingBase(@intFromPtr(pt.global_table) - arch.mem.direct_map_base);
    mem.page_table.releaseKernelPageTable(lock_flag);

    try arch.intr.init();
    try arch.time.init();

    log.info(@src(), "Initialized successfully.", .{});
    is_finished.store(true, .release);

    try root.kernelMain();

    unreachable;
}

extern const __kernel_boot_trampoline_start: [*]const u8;
extern const __kernel_boot_trampoline_end: [*]const u8;
extern fn ap_trampoline_start() callconv(.naked) noreturn;
extern const ap_stack: u64;
extern const ap_entry: u64;
