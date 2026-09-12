const std = @import("std");
const root = @import("root");
const log = root.debug.log;
const hal = root.hal;

pub fn kernelMain() !noreturn {
    try root.time.init();
    try root.sched.init();

    hal.cpu.endlessHalt();
    unreachable;
}
