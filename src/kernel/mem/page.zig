const std = @import("std");
const root = @import("root");
const page = root.hal.page;
const sync = root.sync;
const assert = std.debug.assert;
const log = root.debug.log;

pub const PageType = enum(u8) {
    unavailable = 0,
    tail = 1,
    buddy,
    bucket,
};
pub const PageList = packed struct(u128) {
    _has_next: bool,
    _next: page.PageIndex,
    _has_prev: bool,
    _prev: page.PageIndex,
    _reserved: @Int(.unsigned, 128 - 2 * @bitSizeOf(page.PageIndex) - 2),
    pub inline fn next(self: PageList) ?page.PageIndex {
        return if (self._has_next) self._next else null;
    }
    pub inline fn setNext(self: *PageList, page_index: ?page.PageIndex) void {
        if (page_index) |idx| {
            self._has_next = true;
            self._next = idx;
        } else {
            self._has_next = false;
        }
    }
    pub inline fn prev(self: PageList) ?page.PageIndex {
        return if (self._has_prev) self._prev else null;
    }
    pub inline fn setPrev(self: *PageList, page_index: ?page.PageIndex) void {
        if (page_index) |idx| {
            self._has_prev = true;
            self._prev = idx;
        } else {
            self._has_prev = false;
        }
    }
};
pub const PageCompound = packed struct(u64) {
    order: u8,
    /// The first page.
    head: page.PageIndex,
    _reserved: @Int(.unsigned, 64 - @bitSizeOf(page.PageIndex) - 8) = 0,
};
/// Remember acquire lock before any operation!
pub const PageMeta = extern struct {
    type: PageType,
    _lock: sync.SpinLock,
    _reserved1: u16,
    _refcount: u32,
    compound: PageCompound,
    list: PageList,
    private: u64,
    _reserved2: [3]u64,

    pub inline fn atomicIsType(self: *PageMeta, @"type": PageType) bool {
        return @"type" == @atomicLoad(PageType, &self.type, .acquire);
    }
    pub inline fn lock(self: *PageMeta) sync.SpinLock.Flag {
        return self._lock.lock();
    }
    pub inline fn unlock(self: *PageMeta, flag: sync.SpinLock.Flag) void {
        self._lock.unlock(flag);
    }
};
comptime {
    if (@sizeOf(PageMeta) != 64) {
        @compileError(std.fmt.comptimePrint(
            "@sizeOf(PageMeta) != 64. Current size: {}",
            .{@sizeOf(PageMeta)},
        ));
    }
}

pub inline fn getMeta(page_index: page.PageIndex) *PageMeta {
    return @ptrFromInt(page.page_meta_base + page_index * @sizeOf(PageMeta));
}
