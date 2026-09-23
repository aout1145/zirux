inline fn syscall(number: u64, args: *const [6]u64) u64 {
    return asm volatile (
        \\movq %[number], %%rax
        \\movq %[arg0], %%rdi
        \\movq %[arg1], %%rsi
        \\movq %[arg2], %%rdx
        \\movq %[arg3], %%r10
        \\movq %[arg4], %%r8
        \\movq %[arg5], %%r9
        \\syscall
        : [_] "={rax}" (-> u64),
        : [number] "{rax}" (number),
          [arg0] "{rdi}" (args[0]),
          [arg1] "{rsi}" (args[1]),
          [arg2] "{rdx}" (args[2]),
          [arg3] "{r10}" (args[3]),
          [arg4] "{r8}" (args[4]),
          [arg5] "{r9}" (args[5]),
    );
}

export var stack: [8192]u8 align(4096) = undefined;
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\leaq stack+0x2000, %%rsp
        \\call crtStart
    );
}

var buf = [_]u8{0} ** 65536;

// 8x8 字模，MSB 在左
const font = [8][8]u8{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, // ' '
    .{ 0x04, 0x04, 0x04, 0x3C, 0x44, 0x44, 0x44, 0x3C }, // 'd'
    .{ 0x00, 0x00, 0x38, 0x44, 0x7C, 0x40, 0x44, 0x38 }, // 'e'
    .{ 0x40, 0x40, 0x40, 0x78, 0x44, 0x44, 0x44, 0x44 }, // 'h'
    .{ 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40 }, // 'l'
    .{ 0x00, 0x00, 0x38, 0x44, 0x44, 0x44, 0x44, 0x38 }, // 'o'
    .{ 0x00, 0x00, 0x58, 0x64, 0x40, 0x40, 0x40, 0x40 }, // 'r'
    .{ 0x00, 0x00, 0x44, 0x44, 0x44, 0x54, 0x6C, 0x44 }, // 'w'
};

fn charIndex(c: u8) usize {
    return switch (c) {
        ' ' => 0,
        'd' => 1,
        'e' => 2,
        'h' => 3,
        'l' => 4,
        'o' => 5,
        'r' => 6,
        'w' => 7,
        else => 0,
    };
}

export fn crtStart() callconv(.c) void {
    const path = "/dev/framebuffer0";
    var file_id: u32 = undefined;
    _ = syscall(2, &.{ @intFromPtr(path), path.len, 0x3, @intFromPtr(&file_id), 0, 0 });

    const Info = extern struct {
        width: u32,
        height: u32,
        pixels_per_scan_line: u32,
        pixel_format: u8,
    };
    var info: Info = undefined;
    var info_len: usize = @sizeOf(Info);
    _ = syscall(5, &.{ file_id, 0, @intFromPtr(&info), @intFromPtr(&info_len), 0, 0 });

    const text = "hello world";
    const char_w: u32 = 8;
    const char_h: u32 = 8;
    const bytes_per_pixel: u32 = 4; // 32 位 RGB

    const text_w_orig: u32 = @as(u32, text.len) * char_w; // 88
    const text_h_orig: u32 = char_h; // 8

    // 计算最大整数缩放倍数：受屏幕宽、高以及 buf 容量共同限制
    const max_scale_w = info.width / text_w_orig;
    const max_scale_h = info.height / text_h_orig;
    const max_scale_buf: u32 = @intCast((buf.len / @as(usize, bytes_per_pixel)) / text_w_orig);
    var scale: u32 = @min(@min(max_scale_w, max_scale_h), max_scale_buf);
    if (scale < 1) scale = 1;

    const text_w: u32 = text_w_orig * scale;
    const text_h: u32 = text_h_orig * scale;

    const x0: u32 = if (info.width > text_w) (info.width - text_w) / 2 else 0;
    const y0: u32 = if (info.height > text_h) (info.height - text_h) / 2 else 0;

    const stride: u64 = @as(u64, info.pixels_per_scan_line) * @as(u64, bytes_per_pixel);

    var Y: u32 = 0;
    while (Y < text_h) : (Y += 1) {
        const y_orig: usize = @intCast(Y / scale);
        var X: u32 = 0;
        while (X < text_w) : (X += 1) {
            const x_orig: u32 = X / scale;
            const ch_idx: usize = @intCast(x_orig / char_w);
            const px_in_char: u32 = x_orig % char_w;
            const bits = font[charIndex(text[ch_idx])][y_orig];
            const bit_pos: u3 = @intCast(7 - px_in_char);
            const is_set = (bits >> bit_pos) & 1;
            const v: u8 = if (is_set != 0) 255 else 0;
            const idx = X * bytes_per_pixel;
            buf[idx + 0] = v; // R
            buf[idx + 1] = v; // G
            buf[idx + 2] = v; // B
            buf[idx + 3] = 0; // 32 位填充/Alpha
        }

        var buf_len: usize = @as(usize, text_w) * @as(usize, bytes_per_pixel);
        const offset: u64 =
            @as(u64, y0 + Y) * stride + @as(u64, x0) * @as(u64, bytes_per_pixel);
        _ = syscall(4, &.{ file_id, offset, @intFromPtr(&buf), @intFromPtr(&buf_len), 0, 0 });
    }

    _ = syscall(0, &.{ 0, 0, 0, 0, 0, 0 });
    unreachable;
}
