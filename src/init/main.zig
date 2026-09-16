export fn _start() callconv(.naked) void {
    asm volatile (
        \\movq $0, %%rax
        \\syscall
        \\1:
        \\pause
        \\jmp 1b
    );
}
