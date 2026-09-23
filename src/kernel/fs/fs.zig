const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const assert = std.debug.assert;
const allocator = root.mem.general_allocator;
const hal = root.hal;
const sync = root.sync;
const utils = root.utils;

pub const init_fs = @import("init_fs.zig");
pub const devfs = @import("devfs.zig");

const init_cpu = 0;
pub fn init() !void {
    if (hal.cpu.getLocalCpuId() == init_cpu) {
        const root_path = try allocator.dupe(u8, "/");
        try mount(root_path, init_fs.init());
        const dev_path = try allocator.dupe(u8, "/dev/");
        try mount(dev_path, devfs.init());
    }
}

pub const INode = u64;
pub const FileSystem = struct {
    _refcount: u32,
    vtable: *const VTable,

    pub inline fn ref(self: *FileSystem) void {
        sync.ref(u32, &self._refcount);
    }
    pub inline fn unref(self: *FileSystem) void {
        if (sync.unref(u32, &self._refcount)) {
            self.vtable.deinit(self);
        }
    }

    pub const VTable = struct {
        deinit: *const fn (self: *FileSystem) void,

        open: *const fn (self: *FileSystem, path: []const u8, flags: OpenFlags) OpenError!INode,
        close: *const fn (self: *FileSystem, inode: INode) CloseError!void,

        /// Return the length that actually read
        read: *const fn (self: *FileSystem, inode: INode, offset: usize, buffer: []u8) ReadError!usize,
        /// Return the length that actually write
        write: *const fn (self: *FileSystem, inode: INode, offset: usize, buffer: []const u8) WriteError!usize = noWrite,
        control: *const fn (self: *FileSystem, inode: INode, @"type": usize, buffer: []u8) ControlError!usize = noControl,

        fn noWrite(_: *FileSystem, _: INode, _: usize, _: []const u8) WriteError!usize {
            return WriteError.ReadOnly;
        }
        fn noControl(_: *FileSystem, _: INode, _: usize, _: []u8) ControlError!usize {
            return ControlError.InvalidOperation;
        }
    };
    pub inline fn open(self: *FileSystem, path: []const u8, flags: OpenFlags) OpenError!INode {
        return self.vtable.open(self, path, flags);
    }
    pub inline fn close(self: *FileSystem, inode: INode) CloseError!void {
        return self.vtable.close(self, inode);
    }
    pub inline fn read(self: *FileSystem, inode: INode, offset: usize, buffer: []u8) ReadError!usize {
        return self.vtable.read(self, inode, offset, buffer);
    }
    pub inline fn write(self: *FileSystem, inode: INode, offset: usize, buffer: []const u8) WriteError!usize {
        return self.vtable.write(self, inode, offset, buffer);
    }
    pub inline fn control(self: *FileSystem, inode: INode, @"type": usize, buffer: []u8) ControlError!usize {
        return self.vtable.control(self, inode, @"type", buffer);
    }
};

pub const File = struct {
    inode: INode,
    fs: *FileSystem,
    flags: OpenFlags,
};

const MountPoint = struct {
    node: std.DoublyLinkedList.Node,
    path: []u8,
    fs: *FileSystem,
};
var mount_list_lock: sync.SpinLockIrq = .unlocked;
var mount_list: std.DoublyLinkedList = .{};

/// NOTE: Transfer the ownership of mount_point and fs
pub fn mount(path: []u8, fs: *FileSystem) !void {
    const mount_point = try allocator.create(MountPoint);
    mount_point.* = .{
        .node = undefined,
        .path = path,
        .fs = fs,
    };

    const lock_flag = mount_list_lock.lock();
    defer mount_list_lock.unlock(lock_flag);
    mount_list.append(&mount_point.node);
}
pub fn umount(path: []u8) !void {
    const lock_flag = mount_list_lock.lock();
    defer mount_list_lock.unlock(lock_flag);

    var iter = mount_list.first;
    while (iter) |node| : (iter = node.next) {
        const mount_point: *MountPoint = @fieldParentPtr("node", node);
        if (std.mem.eql(u8, mount_point.path, path)) {
            mount_list.remove(node);
            allocator.free(mount_point.path);
            mount_point.fs.unref();
            allocator.destroy(mount_point);
            return;
        }
    }
    return error.NotFound;
}

pub const OpenFlags = packed struct(u64) {
    writable: bool = false,
    seekable: bool = false,
    _reserved: u62 = 0,

    /// Check the provided flags included by self
    pub fn include(self: OpenFlags, flags: OpenFlags) bool {
        const self_u64: u64 = @bitCast(self);
        const flags_u64: u64 = @bitCast(flags);
        return flags_u64 & ~self_u64 == 0;
    }
};
pub const OpenError = error{
    FileNotFound,
    UnsupportedFlag,
};
pub fn open(path: []const u8, flags: OpenFlags) OpenError!File {
    var optional_fs: ?*FileSystem = null;
    var prefix_len: usize = 0;

    var iter = mount_list.first;
    while (iter) |node| : (iter = node.next) {
        const mount_point: *MountPoint = @fieldParentPtr("node", node);
        if (std.mem.startsWith(u8, path, mount_point.path)) {
            assert(mount_point.path.len != prefix_len);
            if (mount_point.path.len > prefix_len) {
                prefix_len = mount_point.path.len;
                optional_fs = mount_point.fs;
            }
        }
    }

    if (optional_fs) |fs| {
        const inode = try fs.open(path[prefix_len..], flags);
        fs.ref();
        return .{ .inode = inode, .fs = fs, .flags = flags };
    } else {
        return OpenError.FileNotFound;
    }
}

pub const CloseError = error{};
pub inline fn close(file: *File) CloseError!void {
    const result = file.fs.close(file.inode);
    file.fs.unref();
    return result;
}

pub const ReadError = error{
    EndOfFile,
};
pub inline fn read(file: *File, offset: usize, buffer: []u8) ReadError!usize {
    return file.fs.read(file.inode, offset, buffer);
}

pub const WriteError = error{
    ReadOnly,
    TooBig,
};
pub inline fn write(file: *File, offset: usize, buffer: []const u8) WriteError!usize {
    if (!file.flags.writable)
        return WriteError.ReadOnly;
    return file.fs.write(file.inode, offset, buffer);
}

pub const ControlError = error{
    InvalidOperation,
};
pub inline fn control(file: *File, @"type": usize, buffer: []u8) ControlError!usize {
    return file.fs.control(file.inode, @"type", buffer);
}
