export fn _start() callconv(.naked) void {
    asm volatile (
        \\1:
        \\pause
        \\jmp 1b
    );
}
