const std = @import("std");
const root = @import("root");
const hal = root.hal;

pub fn kernelMain() noreturn {
    hal.cpu.endlessHalt();
    unreachable;
}
