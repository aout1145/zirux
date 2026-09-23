const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;
const acpi = root.drivers.acpi;
const intr = arch.intr;
const @"asm" = arch.@"asm";
const io = arch.mem.io;
const hal = root.hal;

const timer_divide: TimerDivide = .div16;
const timer_divisor: u64 = switch (timer_divide) {
    .div2 => 2,
    .div4 => 4,
    .div8 => 8,
    .div16 => 16,
    .div32 => 32,
    .div64 => 64,
    .div128 => 128,
    .div1 => 1,
};
const timer_irq = intr.isr.Vector.lapic_timer.number();

/// See also: https://wiki.osdev.org/APIC_Timer#APIC_Timer_Modes
pub const TimerMode = enum(u2) {
    one_shot = 0,
    periodic = 1,
    tsc_deadline = 2,
};

pub const TimerDivide = enum(u32) {
    div2 = 0b0000,
    div4 = 0b0001,
    div8 = 0b0010,
    div16 = 0b0011,
    div32 = 0b1000,
    div64 = 0b1001,
    div128 = 0b1010,
    div1 = 0b1011,
};

const LvtTimerRegister = packed struct(u32) {
    vector: u8,
    /// 100b if NMI
    nmi_flag: u3,
    _reserved0: u1,
    /// Set if interrupt pending
    delivery_status: bool,
    /// Polarity, set is low triggered
    polarity: bool,
    /// Remote IRR
    remote_irr: bool,
    /// trigger mode, set is level triggered
    trigger: bool,
    /// Set to mask
    masked: bool,
    /// Timer Mode
    timer_mode: TimerMode,
    _reserved1: u13,
};

var bus_hz: u64 linksection(arch.cpu.per_cpu.section) = undefined;
pub fn init() !void {
    const flag = intr.irqSave();
    defer intr.irqRestore(flag);

    const wait_us = 20_000; // 20ms
    arch.cpu.per_cpu.write(u64, &bus_hz, try calibrate(wait_us));

    intr.isr.setHandler(timer_irq, timerHandler);
    setTimerDivide(timer_divide);
}
fn calibrate(wait_us: u32) !u64 {
    setTimerDivide(.div1);
    configureLvtTimer(0, .one_shot, true);

    const large_count = 0xFFFFFFFF;
    setInitialCount(large_count);

    const clock_source = if (root.drivers.time.hpet.hpet) |*hpet| blk: {
        break :blk hpet;
    } else {
        return error.ClockSourceUnavailable;
    };
    const start_count = clock_source.getCount();
    const diff_count = clock_source.getHz() * wait_us / 1_000_000;
    clock_source.setStatus(.running);
    while (clock_source.getCount() - start_count < diff_count) {
        @"asm".pause();
    }
    clock_source.setStatus(.stopped);

    const current = getCurrentCount();
    const elapsed = large_count - current;
    if (elapsed == 0) return error.CalibrationFailed;

    const ret_bus_hz = @as(u64, elapsed) * 1_000_000 / wait_us;
    if (ret_bus_hz == 0) return error.CalibrationFailed;

    setInitialCount(0);
    return ret_bus_hz;
}
fn timerHandler(ctx: *arch.cpu.context.Context) void {
    const optional_handler = arch.cpu.per_cpu.read(?hal.time.TimerDevice.Handler, &apic_timer.handler);
    if (optional_handler) |handler| {
        handler(@ptrCast(ctx), arch.cpu.per_cpu.ptr(hal.time.TimerDevice, &apic_timer));
    }
    intr.apic.sendEoi();
}

inline fn setTimerDivide(divide: TimerDivide) void {
    intr.apic.lapicWrite(.divide_conf, @intFromEnum(divide));
}
inline fn configureLvtTimer(vector: u8, mode: TimerMode, masked: bool) void {
    const lvt = std.mem.zeroInit(LvtTimerRegister, .{
        .vector = vector,
        .timer_mode = mode,
        .masked = masked,
    });
    intr.apic.lapicWrite(.lvt_timer, @bitCast(lvt));
}
inline fn setInitialCount(count: u32) void {
    intr.apic.lapicWrite(.initial_cnt, count);
}
inline fn getCurrentCount() u32 {
    return intr.apic.lapicRead(.current_cnt);
}

// const pit = struct {
//     const freq = 1_193_182; // 1.193182 MHz
//     const port_data2 = 0x42;
//     const port_cmd = 0x43;
//     const port_61 = 0x61;

//     var pit_lock: root.sync.SpinLockIrq = .unlocked;

//     fn delayUs(us: u32) !void {
//         const count = @as(u64, freq) * us / 1_000_000;
//         if (count > 0xFFFF) return error.DelayTooLong;

//         // Enable the channel 2 gate (bit 0), disable the speaker (bit 1).
//         io.outb((io.inb(port_61) & 0xFD) | 0x01, port_61);

//         // channel 2, lobyte/hibyte, mode 0, binary
//         io.outb(0xB0, port_cmd);
//         io.outb(@truncate(count), port_data2);
//         io.outb(@truncate(count >> 8), port_data2);

//         // Wait for channel 2 OUT (port 0x61 bit 5) to go high: terminal count.
//         while ((io.inb(port_61) & 0x20) == 0) {
//             @"asm".pause();
//         }
//     }

//     fn calibrate(wait_us: u32) !u64 {
//         const lock_flag = pit_lock.lock();
//         defer pit_lock.unlock(lock_flag);

//         setTimerDivide(.div1);
//         configureLvtTimer(0, .one_shot, true);

//         const large_count = 0xFFFFFFFF;
//         setInitialCount(large_count);

//         try delayUs(wait_us);

//         const current = getCurrentCount();
//         const elapsed = large_count - current;
//         if (elapsed == 0) return error.CalibrationFailed;

//         const ret_bus_hz = @as(u64, elapsed) * 1_000_000 / wait_us;
//         if (ret_bus_hz == 0) return error.CalibrationFailed;

//         setInitialCount(0);
//         return ret_bus_hz;
//     }
// };

const vtable: hal.time.TimerDevice.VTable = .{
    .setPeriodic = setPeriodic,
    .setOneshot = setOneshot,
    .shutdown = shutdown,
};
pub var apic_timer: hal.time.TimerDevice linksection(arch.cpu.per_cpu.section) = .{
    .handler = null,
    .vtable = &vtable,
};
inline fn start(mode: TimerMode, ms: u64) void {
    const local_bus_hz = arch.cpu.per_cpu.read(u64, &bus_hz);
    const init_count = local_bus_hz * ms / timer_divisor / 1000;
    assert(init_count != 0 and init_count <= 0xFFFFFFFF);
    configureLvtTimer(timer_irq, mode, false);
    setInitialCount(@intCast(init_count));
}
fn setPeriodic(_: *hal.time.TimerDevice, ms: u64) void {
    start(.periodic, ms);
}
fn setOneshot(_: *hal.time.TimerDevice, ms: u64) void {
    start(.one_shot, ms);
}
fn shutdown(_: *hal.time.TimerDevice) void {
    configureLvtTimer(timer_irq, .one_shot, true);
    setInitialCount(0);
}
