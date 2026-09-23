const std = @import("std");
const root = @import("root");
const fs = root.fs;
const assert = std.debug.assert;

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

pub const PixelFormat = enum(u8) {
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
fn control(device: *fs.devfs.DeviceOperations, @"type": usize, buffer: []u8) fs.ControlError!usize {
    const control_type_get_info = 0;
    const Info = extern struct {
        width: u32,
        height: u32,
        pixels_per_scan_line: u32,
        pixel_format: PixelFormat,
    };

    const fb: *FrameBuffer = @fieldParentPtr("interface", device);
    switch (@"type") {
        control_type_get_info => {
            const info: Info = .{
                .width = fb.width,
                .height = fb.height,
                .pixels_per_scan_line = fb.pixels_per_scan_line,
                .pixel_format = fb.pixel_format,
            };
            const copy_len = @min(buffer.len, @sizeOf(Info));
            @memcpy(buffer[0..copy_len], std.mem.asBytes(&info)[0..copy_len]);
            return copy_len;
        },
        else => return fs.ControlError.InvalidOperation,
    }
}
const vtable: fs.devfs.DeviceOperations.VTable = .{
    .read = read,
    .write = write,
    .control = control,
};
