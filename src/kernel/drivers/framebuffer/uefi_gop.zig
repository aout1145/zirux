const std = @import("std");
const root = @import("root");
const fb = root.drivers.framebuffer;
const arch = root.arch.x86_64;
const mem = root.mem;
const allocator = root.mem.general_allocator;

pub fn init(fb_info: arch.boot.defs.FrameBufferInfo) !void {
    const io_region = try mem.vmap.ioMap(
        fb_info.frame_buffer_base,
        fb_info.frame_buffer_size,
        .write_combining,
    );
    const buffer: [*]u8 = @ptrFromInt(io_region.base);

    const framebuffer = try allocator.create(fb.FrameBuffer);
    framebuffer.* = .{
        .buffer = buffer[0..fb_info.frame_buffer_size],
        .width = fb_info.horizontal_resolution,
        .height = fb_info.vertical_resolution,
        .pixel_format = switch (fb_info.pixel_format) {
            .rgb => .red_green_blue_reserved,
            .bgr => .blue_green_red_reserved,
        },
        .pixels_per_scan_line = fb_info.pixels_per_scan_line,
    };
    try framebuffer.register();
}
