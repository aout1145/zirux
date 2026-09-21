const root = @import("root");

pub const PhysAddr = u64;
pub const VirtAddr = u64;

const gib = root.mem.gib;
const tib = root.mem.tib;
pub const user_base: usize = 0x0000000000000000;
pub const user_size: usize = 128 * tib;
pub const direct_map_base: usize = 0xFFFF880000000000;
pub const direct_map_size: usize = 64 * tib;
pub const virtual_map_base: usize = 0xFFFFC90000000000;
pub const virtual_map_size: usize = 32 * tib;
pub const page_meta_base: usize = 0xFFFFEA0000000000;
pub const page_meta_size: usize = 1 * tib;
pub const efi_runtime_base: usize = 0xFFFFFFEF00000000;
pub const efi_runtime_size: usize = 64 * gib;
pub const kernel_base: usize = 0xFFFFFFFF80000000;
pub const kernel_size: usize = 2 * gib;

pub const page = @import("page.zig");
pub const io = @import("io.zig");
