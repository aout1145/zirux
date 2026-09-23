const std = @import("std");
const root = @import("root");
const fs = root.fs;
const assert = std.debug.assert;

const file: []const u8 = @embedFile("init_elf");

pub fn init() *fs.FileSystem {
    init_fs.ref();
    return &init_fs;
}

fn deinit(_: *fs.FileSystem) void {
    unreachable;
}

fn open(_: *fs.FileSystem, path: []const u8, flags: fs.OpenFlags) fs.OpenError!fs.INode {
    if (!supported_flags.include(flags))
        return fs.OpenError.UnsupportedFlag;
    if (!std.mem.eql(u8, "init", path))
        return fs.OpenError.FileNotFound;
    return 0;
}
fn close(_: *fs.FileSystem, inode: fs.INode) fs.CloseError!void {
    assert(inode == 0);
}

fn read(_: *fs.FileSystem, inode: fs.INode, offset: usize, buffer: []u8) fs.ReadError!usize {
    assert(inode == 0);
    if (offset >= file.len)
        return fs.ReadError.EndOfFile;
    const offset_file = file[offset..];
    const copy_len = @min(offset_file.len, buffer.len);
    @memcpy(buffer[0..copy_len], offset_file[0..copy_len]);
    return copy_len;
}

const supported_flags: fs.OpenFlags = .{
    .seekable = true,
    .writable = false,
};
var init_fs: fs.FileSystem = .{
    ._refcount = 1,
    .vtable = &vtable,
};
const vtable: fs.FileSystem.VTable = .{
    .deinit = deinit,
    .open = open,
    .close = close,
    .read = read,
};
