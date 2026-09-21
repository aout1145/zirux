const std = @import("std");
const root = @import("root");
const fs = root.fs;

pub const uefi_gop = @import("uefi_gop.zig");

pub const FrameBuffer = struct {
    interface: fs.devfs.DeviceOperations = .{
        .supported_flags = .{
            .seekable = true,
            .writable = true,
        },
        .vtable = &vtable,
    },

    buffer: []u8,
    width: u32,
    height: u32,
    pixel_format: PixelFormat,
    pixels_per_scan_line: u32,

    pub fn register(self: *FrameBuffer) !void {
        try fs.devfs.register("framebuffer", &self.interface);
    }
};

pub const PixelFormat = enum {
    /// red_green_blue_reserved_8_bit_per_color
    red_green_blue_reserved,
    /// blue_green_red_reserved_8_bit_per_color
    blue_green_red_reserved,
};

fn read(device: *fs.devfs.DeviceOperations, offset: usize, buffer: []u8) fs.ReadError!usize {
    const fb: *FrameBuffer = @fieldParentPtr("interface", device);
    if (offset >= fb.buffer.len)
        return fs.ReadError.EndOfFile;
    const offset_fb = fb.buffer[offset..];
    const copy_len = @min(offset_fb.len, buffer.len);
    @memcpy(buffer[0..copy_len], offset_fb[0..copy_len]);
    return copy_len;
}
fn write(device: *fs.devfs.DeviceOperations, offset: usize, buffer: []const u8) fs.WriteError!usize {
    const fb: *FrameBuffer = @fieldParentPtr("interface", device);
    if (offset >= fb.buffer.len)
        return fs.WriteError.TooBig;
    const offset_fb = fb.buffer[offset..];
    const copy_len = @min(offset_fb.len, buffer.len);
    @memcpy(offset_fb[0..copy_len], buffer[0..copy_len]);
    return copy_len;
}
const vtable: fs.devfs.DeviceOperations.VTable = .{
    .read = read,
    .write = write,
};
