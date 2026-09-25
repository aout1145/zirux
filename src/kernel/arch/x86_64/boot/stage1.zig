const std = @import("std");
const root = @import("root");
const mem = root.arch.x86_64.mem;
const page = root.arch.x86_64.mem.page;
const @"asm" = root.arch.x86_64.@"asm";

const stage2 = @import("stage2.zig");
const defs = @import("defs.zig");

var boot_stack: [2 * page.page_size]u8 align(page.page_size) linksection(".boot") = undefined;
var boot_page_table: [4][page.page_size]u8 align(page.page_size) linksection(".boot") = undefined;

pub fn _start() linksection(".boot") callconv(.naked) noreturn {
    // Switch to initializing stack immediately
    asm volatile (
        \\cli
        \\movq %[new_stack], %%rsp
        \\call kernelEntry
        :
        : [new_stack] "r" (@intFromPtr(&boot_stack) + boot_stack.len - 0x10),
        : .{ .rdi = true });
}

export fn kernelEntry(boot_info: *defs.BootInfo) linksection(".boot") callconv(.{ .x86_64_sysv = .{} }) noreturn {
    // Running under low address...
    // We prepare temporary page table
    // Only map 512gb physical + 1gb kernel
    const lv4_tbl: *[512]page.Table = @ptrCast(&boot_page_table[0]);
    const lv3_tbl1: *[512]page.Page1Gib = @ptrCast(&boot_page_table[1]);
    const lv3_tbl2: *[512]page.Page1Gib = @ptrCast(&boot_page_table[2]);
    const lv3_tbl3: *[512]page.Page1Gib = @ptrCast(&boot_page_table[3]);
    for (0..512) |i| {
        const gib = root.mem.gib;
        // Identity mapping
        map1Gib(lv4_tbl, lv3_tbl1, i * gib, i * gib);
        // Direct mapping area
        map1Gib(lv4_tbl, lv3_tbl3, mem.direct_map_base + i * gib, i * gib);
    }
    // Kernel area
    map1Gib(lv4_tbl, lv3_tbl2, mem.kernel_base, 0);
    // Now we can switch to high address
    @"asm".writeRegister("cr3", @intFromPtr(lv4_tbl));
    stage2._start(boot_info);
    unreachable;
}

fn map1Gib(lv4_tbl: *[512]page.Table, lv3_tbl: *[512]page.Page1Gib, virt: u64, phys: u64) linksection(".boot") void {
    const lv4_idx = page.levelIndex(.level4, virt);
    const lv3_idx = page.levelIndex(.level3, virt);
    if (!lv4_tbl[lv4_idx].present) {
        lv4_tbl[lv4_idx] = page.Table{
            .present = true,
            .phys = @truncate(@intFromPtr(lv3_tbl) >> page.page_shift),
            .rw = true,
            .us = false,
            .xd = false,
            .pcd = false,
            .pwt = false,
        };
    }
    lv3_tbl[lv3_idx] = page.Page1Gib{
        .present = true,
        .phys = @truncate(phys >> page.levelShift(.level3)),
        .rw = true,
        .us = false,
        .xd = false,
        .global = false,
        .pat = false,
        .pcd = false,
        .pk = 0,
        .pwt = false,
    };
}
