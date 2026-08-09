const std = @import("std");

pub const magic: usize = 0xDEADBEEF_ABACDEFE;

pub const BootInfo = extern struct {
    magic: usize,
    uefi_system_table_base: usize,
    memory_map: MemoryMapInfo,
    framebuffer_info: FrameBufferInfo,
};

pub const MemoryMapInfo = extern struct {
    base: usize,
    len: usize,
    descriptor_size: usize,
    descriptor_version: u32,
};

pub const FrameBufferInfo = extern struct {
    available: bool,
    frame_buffer_base: usize,
    frame_buffer_size: usize,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixel_format: PixelFormat,
    pixels_per_scan_line: u32,
    pub const PixelFormat = enum(u8) {
        rgb,
        bgr,
    };
};
