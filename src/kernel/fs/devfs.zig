const std = @import("std");
const root = @import("root");
const fs = root.fs;
const assert = std.debug.assert;
const allocator = root.mem.general_allocator;

pub fn init() *fs.FileSystem {
    devfs.ref();
    return &devfs;
}

pub const DeviceOperations = struct {
    supported_flags: fs.OpenFlags,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Return the length that actually read
        read: *const fn (self: *DeviceOperations, offset: usize, buffer: []u8) fs.ReadError!usize,
        /// Return the length that actually write
        write: *const fn (self: *DeviceOperations, offset: usize, buffer: []const u8) fs.WriteError!usize,
    };
    pub inline fn read(self: *DeviceOperations, offset: usize, buffer: []u8) fs.ReadError!usize {
        return self.vtable.read(self, offset, buffer);
    }
    pub inline fn write(self: *DeviceOperations, offset: usize, buffer: []const u8) fs.WriteError!usize {
        return self.vtable.write(self, offset, buffer);
    }
};

const DeviceNode = struct {
    name: []u8,
    number: u32,
    inode: fs.INode,
    device: *DeviceOperations,
};
var devices: root.utils.IdAllocator(fs.INode, DeviceNode) = .empty;

pub fn register(name: []const u8, device: *DeviceOperations) !void {
    var number: u32 = 0;
    var iter = devices.iterator();
    while (iter.next()) |node| {
        if (std.mem.eql(u8, node.name, name)) {
            number = @max(number, node.number);
        }
    }
    iter.deinit();

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    _ = try devices.alloc(allocator, .{
        .name = owned_name,
        .number = number,
        .inode = undefined,
        .device = device,
    }, "inode");
}

var devfs: fs.FileSystem = .{
    ._refcount = 1,
    .vtable = &vtable,
};
fn deinit(_: *fs.FileSystem) void {
    unreachable;
}
fn open(_: *fs.FileSystem, path: []const u8, flags: fs.OpenFlags) fs.OpenError!fs.INode {
    var iter = devices.iterator();
    defer iter.deinit();
    while (iter.next()) |node| {
        if (std.mem.eql(u8, node.name, path)) {
            if (!node.device.supported_flags.include(flags)) {
                return fs.OpenError.UnsupportedFlag;
            }
            return node.inode;
        }
    }
    return fs.OpenError.FileNotFound;
}
fn close(_: *fs.FileSystem, _: fs.INode) fs.CloseError!void {}
fn read(_: *fs.FileSystem, inode: fs.INode, offset: usize, buffer: []u8) fs.ReadError!usize {
    // Device nodes are never freed after registration, so the lock can be
    // released before performing the (potentially blocking) I/O.
    var locked_node = devices.get(inode);
    const node = locked_node.value orelse unreachable;
    locked_node.unlock();
    return node.device.read(offset, buffer);
}
fn write(_: *fs.FileSystem, inode: fs.INode, offset: usize, buffer: []const u8) fs.WriteError!usize {
    var locked_node = devices.get(inode);
    const node = locked_node.value orelse unreachable;
    locked_node.unlock();
    return node.device.write(offset, buffer);
}
const vtable: fs.FileSystem.VTable = .{
    .deinit = deinit,
    .open = open,
    .close = close,
    .read = read,
    .write = write,
};
