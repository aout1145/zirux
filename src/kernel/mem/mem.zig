const std = @import("std");
const root = @import("root");
const hal_page = root.hal.page;

pub const bootmm = @import("bootmm.zig");
pub const page = @import("page.zig");
pub const page_table = @import("page_table.zig");
pub const buddy = @import("buddy.zig");
pub const bucket = @import("bucket.zig");

pub const kib: comptime_int = 1024;
pub const mib: comptime_int = 1024 * kib;
pub const gib: comptime_int = 1024 * mib;
pub const tib: comptime_int = 1024 * gib;
