const std = @import("std");
const root = @import("root");
const arch = root.arch.x86_64;
const assert = std.debug.assert;
const log = root.debug.log;
const acpi = root.drivers.acpi;
const intr = arch.intr;
const @"asm" = arch.@"asm";
const io = arch.mem.io;

const timer_divide: TimerDivide = .div16;
const timer_irq = intr.isr.Vector.timer.number();

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

pub fn init() !void {
    const flag = intr.irqSave();
    defer intr.irqRestore(flag);

    const wait_us = 10_000; // 10ms
    const bus_hz = try pit.calibrate(wait_us);

    const divisor: u64 = switch (timer_divide) {
        .div2 => 2,
        .div4 => 4,
        .div8 => 8,
        .div16 => 16,
        .div32 => 32,
        .div64 => 64,
        .div128 => 128,
        .div1 => 1,
    };
    const init_count = bus_hz / divisor / root.time.tick.tick_ms;
    if (init_count == 0 or init_count > 0xFFFFFFFF) {
        return error.InvalidTimerFrequency;
    }

    intr.isr.setHandler(timer_irq, timerHandler);
    setTimerDivide(timer_divide);
    configureLvtTimer(timer_irq, .periodic, false);
    setInitialCount(@intCast(init_count));
}

fn timerHandler(ctx: *arch.cpu.context.Context) void {
    root.time.tick.handler(@ptrCast(ctx));
    intr.apic.sendEoi();
}

fn setTimerDivide(divide: TimerDivide) void {
    intr.apic.lapicWrite(.divide_conf, @intFromEnum(divide));
}

fn configureLvtTimer(vector: u8, mode: TimerMode, masked: bool) void {
    const lvt = std.mem.zeroInit(LvtTimerRegister, .{
        .vector = vector,
        .timer_mode = mode,
        .masked = masked,
    });
    intr.apic.lapicWrite(.lvt_timer, @bitCast(lvt));
}

fn setInitialCount(count: u32) void {
    intr.apic.lapicWrite(.initial_cnt, count);
}

fn getCurrentCount() u32 {
    return intr.apic.lapicRead(.current_cnt);
}

const pit = struct {
    const freq = 1_193_182; // 1.193182 MHz
    const port_data0 = 0x40;
    const port_data1 = 0x41;
    const port_data2 = 0x42;
    const port_cmd = 0x43;

    fn delayUs(us: u32) !void {
        const count = @as(u64, freq) * us / 1_000_000;
        if (count >= 0xFFFF) return error.DelayTooLong;

        // 0x34: channel 0, lobyte/hibyte, mode 3, 16-bit binary
        io.outb(0x36, port_cmd);

        io.outb(@truncate(count), port_data0);
        io.outb(@truncate(count >> 8), port_data0);

        while (io.inb(port_data0) != 0) {
            @"asm".pause();
        }
    }

    fn calibrate(wait_us: u32) !u64 {
        setTimerDivide(.div1);
        configureLvtTimer(0, .one_shot, true);

        const large_count = 0xFFFFFFFF;
        setInitialCount(large_count);

        try delayUs(wait_us);

        const current = getCurrentCount();
        const elapsed = large_count - current;
        if (elapsed == 0) return error.CalibrationFailed;

        const bus_hz = @as(u64, elapsed) * 1_000_000 / wait_us;
        if (bus_hz == 0) return error.CalibrationFailed;

        return bus_hz;
    }
};
