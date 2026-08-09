const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const log = root.debug.log;
const mem = root.mem;
const assert = std.debug.assert;

const defs = @import("defs.zig");

var kernel_stack: [4 * arch.mem.page.page_size]u8 align(arch.mem.page.page_size) = undefined;

pub fn _start(_: *defs.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn {
    // Switch to stack in high address
    asm volatile (
        \\cli
        \\movq %[new_stack], %%rsp
        \\call kernelEntry2
        :
        : [new_stack] "r" (@intFromPtr(&kernel_stack) + kernel_stack.len - 0x10),
    );
    unreachable;
}

export fn kernelEntry2(boot_info: *defs.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn {
    kernelMain(boot_info) catch |e| @panic(@errorName(e));
    unreachable;
}

fn kernelMain(boot_info: *defs.BootInfo) !void {
    // Now we enable full kernel address space!
    arch.debug.init();
    log.info(@src(), "Booting...", .{});
    if (boot_info.magic != defs.magic) {
        return error.InvalidMagic;
    }

    try initMem(boot_info.memory_map, boot_info.uefi_system_table_base);

    while (true) asm volatile ("hlt");
}

var init_mm: [2][mem.bootmm.requested_size]u8 align(mem.bootmm.requested_align) linksection(".init") = undefined;

fn initMem(info: defs.MemoryMapInfo, uefi_system_table_base: usize) !void {
    const uefi = std.os.uefi;

    // Initialize part of memory first
    mem.bootmm.init(&init_mm);
    for (0..info.len) |i| {
        const desc: *uefi.tables.MemoryDescriptor = @ptrFromInt(info.base + i * info.descriptor_size);
        switch (desc.type) {
            .conventional_memory,
            .boot_services_code,
            .loader_code,
            => {
                try mem.bootmm.add(
                    desc.physical_start,
                    desc.number_of_pages * arch.mem.page.page_size,
                    .usable,
                );
            },
            .boot_services_data => {
                try mem.bootmm.add(
                    desc.physical_start,
                    desc.number_of_pages * arch.mem.page.page_size,
                    .no_alloc,
                );
            },
            .loader_data => {
                const text_start = @intFromPtr(&__kernel_text_start) - arch.mem.kernel_base;
                const recyclable_size = text_start - desc.physical_start;
                assert(recyclable_size % arch.mem.page.page_size == 0);
                try mem.bootmm.add(
                    desc.physical_start,
                    recyclable_size,
                    .no_alloc,
                );
                const unrecyclable_size = desc.number_of_pages * arch.mem.page.page_size - recyclable_size;
                assert(unrecyclable_size % arch.mem.page.page_size == 0);
                try mem.bootmm.add(
                    desc.physical_start + recyclable_size,
                    unrecyclable_size,
                    .occupied,
                );
            },
            .acpi_reclaim_memory => {
                try mem.bootmm.add(
                    desc.physical_start,
                    desc.number_of_pages * arch.mem.page.page_size,
                    .occupied,
                );
            },
            .runtime_services_code,
            .runtime_services_data,
            .unusable_memory,
            .acpi_memory_nvs,
            .reserved_memory_type,
            => {
                try mem.bootmm.add(
                    desc.physical_start,
                    desc.number_of_pages * arch.mem.page.page_size,
                    .no_map,
                );
            },
            else => {
                log.info(@src(), "unsupported memory type: {s}", .{@tagName(desc.type)});
                log.info(@src(), "0x{x} - 0x{x}", .{
                    desc.physical_start,
                    desc.physical_start + desc.number_of_pages * arch.mem.page.page_size,
                });
            },
        }
    }

    // Construct full page table
    arch.mem.page.init();
    const pt = try mem.page_table.PageTable.init(mem.bootmm.allocator);
    // 1. Kernel area
    try mapKernel(@intFromPtr(&__kernel_text_start), @intFromPtr(&__kernel_text_end), pt, .{
        .writable = false,
        .executable = true,
        .userspace = false,
        .global = true,
        .cache_policy = .write_back,
    });
    try mapKernel(@intFromPtr(&__kernel_rodata_start), @intFromPtr(&__kernel_rodata_end), pt, .{
        .writable = false,
        .executable = false,
        .userspace = false,
        .global = true,
        .cache_policy = .write_back,
    });
    try mapKernel(@intFromPtr(&__kernel_data_start), @intFromPtr(&__kernel_data_end), pt, .{
        .writable = true,
        .executable = false,
        .userspace = false,
        .global = true,
        .cache_policy = .write_back,
    });
    try mapKernel(@intFromPtr(&__kernel_bss_start), @intFromPtr(&__kernel_bss_end), pt, .{
        .writable = true,
        .executable = false,
        .userspace = false,
        .global = true,
        .cache_policy = .write_back,
    });
    // 2. Direct mapping area
    try mem.bootmm.makeDirectMap(pt);
    // 3. Page metadata area
    try mem.bootmm.makePageMetadata(pt);
    // 4. UEFI Runtime services area
    var efi_vaddr: usize = arch.mem.efi_runtime_base;
    var system_table_vaddr: usize = 0;
    for (0..info.len) |i| {
        const desc: *uefi.tables.MemoryDescriptor = @ptrFromInt(info.base + i * info.descriptor_size);
        if (!desc.attribute.memory_runtime) continue;

        try pt.mapRange(
            mem.bootmm.allocator,
            efi_vaddr,
            desc.physical_start,
            desc.number_of_pages,
            .{
                .writable = !(desc.attribute.ro or desc.attribute.wp),
                .executable = !desc.attribute.xp,
                .userspace = false,
                .global = true,
                .cache_policy = blk: {
                    if (desc.attribute.wb) {
                        break :blk .write_back;
                    } else if (desc.attribute.wc) {
                        break :blk .write_combining;
                    } else if (desc.attribute.wt) {
                        break :blk .write_through;
                    } else {
                        break :blk .uncacheable;
                    }
                },
            },
        );
        desc.virtual_start = efi_vaddr;

        if (uefi_system_table_base >= desc.physical_start and
            uefi_system_table_base < desc.physical_start + desc.number_of_pages * arch.mem.page.page_size)
        {
            system_table_vaddr = efi_vaddr + uefi_system_table_base - desc.physical_start;
        }

        efi_vaddr += desc.number_of_pages * arch.mem.page.page_size;
    }
    const system_table_phys: *std.os.uefi.tables.SystemTable = @ptrFromInt(uefi_system_table_base);
    try system_table_phys.runtime_services.setVirtualAddressMap(.{
        .ptr = @ptrFromInt(info.base),
        .info = .{
            .key = undefined,
            .len = info.len,
            .descriptor_size = info.descriptor_size,
            .descriptor_version = info.descriptor_version,
        },
    });
    // Finally, switch to new page table
    arch.mem.page.writePagingBase(@intFromPtr(pt.global_table) - arch.mem.direct_map_base);

    // Deinitialize bootmm, switch to buddy
    mem.bootmm.switchToBuddy();

    log.info(@src(), "Initailized memory.", .{});
}

fn mapKernel(start: u64, end: u64, pt: mem.page_table.PageTable, attr: root.hal.page.PageAttribute) !void {
    const phys_addr = start - arch.mem.kernel_base;
    const virt_addr = arch.mem.kernel_base + phys_addr;
    const page_num = (end - start) / arch.mem.page.page_size;
    try pt.mapRange(mem.bootmm.allocator, virt_addr, phys_addr, page_num, attr);
}

extern const __kernel_text_start: [*]const u8;
extern const __kernel_text_end: [*]const u8;
extern const __kernel_rodata_start: [*]const u8;
extern const __kernel_rodata_end: [*]const u8;
extern const __kernel_data_start: [*]const u8;
extern const __kernel_data_end: [*]const u8;
extern const __kernel_bss_start: [*]const u8;
extern const __kernel_bss_end: [*]const u8;
