const std = @import("std");
const root = @import("root");

const println = root.hal.debug.println;

inline fn log(
    comptime level: []const u8,
    comptime src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buffer: [128]u8 = undefined;
    const prefix = std.fmt.bufPrint(
        &buffer,
        "[CPU#{}] {s} {s}:{} ",
        .{ root.hal.cpu.getLocalCpuId(), level, src.file, src.line },
    ) catch unreachable;
    println(prefix, fmt, args);
}
pub inline fn debug(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").mode == .Debug) {
        log("DEBUG", src, fmt, args);
    }
}
pub inline fn info(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log("INFO ", src, fmt, args);
}
pub inline fn warn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log("WARN ", src, fmt, args);
}
pub inline fn err(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log("ERROR", src, fmt, args);
}
