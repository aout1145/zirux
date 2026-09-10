const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;

const apic = @import("apic.zig");

var lock: root.sync.SpinLockIrq = .unlocked;

pub const InterruptCommandRegisterLow = packed struct(u32) {
    // The vector number, or starting page number for SIPIs
    vector: u8,
    delivery_mode: DeliveryMode,
    destination_mode: DestinationMode,
    delivery_status: DeliveryStatus,
    _reserved0: u5,
    destination_type: DestinationType,
    _reserved2: u12,

    pub const DeliveryMode = enum(u3) {
        normal = 0,
        lowest_priority = 1,
        smi = 2,
        nmi = 4,
        init = 5,
        sipi = 6,
    };
    pub const DestinationMode = enum(u1) {
        physical = 0,
        logical = 1,
    };
    pub const DeliveryStatus = enum(u1) {
        ready = 0,
        busy = 1,
    };
    pub const DestinationType = enum(u2) {
        icr_high = 0,
        self = 1,
        /// All Including Self
        all = 2,
        /// All Excluding Self
        others = 3,
    };
};

pub const InterruptCommandRegisterHigh = packed struct(u32) {
    _reserved0: u24,
    target_processor: u8,
};

pub fn sendRaw(
    target: u8,
    vector: u8,
    @"type": InterruptCommandRegisterLow.DestinationType,
    mode: InterruptCommandRegisterLow.DeliveryMode,
) void {
    const flag = lock.lock();
    defer lock.unlock(flag);

    while (true) {
        const icr_low: InterruptCommandRegisterLow = @bitCast(apic.lapicRead(.icr_low));
        if (icr_low.delivery_status == .ready)
            break;
        arch.@"asm".pause();
    }

    const icr_high: InterruptCommandRegisterHigh = .{
        .target_processor = target,
        ._reserved0 = 0,
    };
    apic.lapicWrite(.icr_high, @bitCast(icr_high));

    var icr_low: InterruptCommandRegisterLow = @bitCast(apic.lapicRead(.icr_low));
    icr_low.vector = vector;
    icr_low.delivery_mode = mode;
    icr_low.destination_type = @"type";
    icr_low.destination_mode = .physical;
    apic.lapicWrite(.icr_low, @bitCast(icr_low));
}

pub inline fn send(target: u16, vector: u8) void {
    sendRaw(@intCast(target), vector, .icr_high, .normal);
}
pub inline fn broadcastAll(vector: u8) void {
    sendRaw(0, vector, .all, .normal);
}
pub inline fn broadcastOthers(vector: u8) void {
    sendRaw(0, vector, .others, .normal);
}
