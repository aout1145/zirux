const std = @import("std");
const root = @import("root");
const log = root.debug.log;

pub fn kernelMain() !noreturn {
    try root.fs.init();
    try root.sched.init();
    try root.time.init();

    root.hal.cpu.endlessHalt();
    unreachable;
}
