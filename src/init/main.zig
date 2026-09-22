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
const buf = [_]u8{255} ** 4096;
export fn crtStart() callconv(.c) void {
    const path = "/dev/framebuffer";
    var file_id: u32 = undefined;
    _ = syscall(2, &.{ @intFromPtr(path), path.len, 0x3, @intFromPtr(&file_id), 0, 0 });

    var len = buf.len;
    _ = syscall(4, &.{ file_id, 0, @intFromPtr(&buf), @intFromPtr(&len), 0, 0 });

    _ = syscall(0, &.{ 0, 0, 0, 0, 0, 0 });
    unreachable;
}
