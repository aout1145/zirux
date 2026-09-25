BOOT_TRAMPOLINE_BASE = 0x8000;
KERNEL_PADDR_TEXT = 0x0000000000200000;
KERNEL_VADDR_BASE = 0xFFFFFFFF80000000;
KERNEL_VADDR_TEXT = 0xFFFFFFFF80200000;

SECTIONS {
    . = BOOT_TRAMPOLINE_BASE;

    __kernel_boot_trampoline_start = . - BOOT_TRAMPOLINE_BASE + KERNEL_PADDR_TEXT + KERNEL_VADDR_BASE;
    .boot_trampoline 0x8000 : AT (KERNEL_PADDR_TEXT) {
        *(.boot_trampoline)
    }
    . = ALIGN(4K);
    __kernel_boot_trampoline_end = . - BOOT_TRAMPOLINE_BASE + KERNEL_PADDR_TEXT + KERNEL_VADDR_BASE;

    . = KERNEL_PADDR_TEXT + SIZEOF(.boot_trampoline);
    . = ALIGN(4K);

    __kernel_boot_start = . + KERNEL_VADDR_BASE;
    .boot ALIGN(4K) : AT(ADDR(.boot)) {
        *(.boot)
    }
    . = ALIGN(4K);
    __kernel_boot_end = . + KERNEL_VADDR_BASE;

    __kernel_per_cpu_start = . + KERNEL_VADDR_BASE;
    .per_cpu ALIGN(4K) : AT(ADDR(.per_cpu)) {
        *(.per_cpu)
    }
    . = ALIGN(4K);
    __kernel_per_cpu_end = . + KERNEL_VADDR_BASE;

    . = KERNEL_VADDR_BASE + .;
    . = ALIGN(4K);

    __kernel_init_start = .;
    .init ALIGN(4K) : AT (ADDR(.init) - KERNEL_VADDR_BASE) {
        *(.init)
    }
    . = ALIGN(4K);
    __kernel_init_end = .;

    __kernel_text_start = .;
    .text ALIGN(4K) : AT (ADDR(.text) - KERNEL_VADDR_BASE) {
        *(.text .text.*)
        *(.ltext)
    }
    . = ALIGN(4K);
    __kernel_text_end = .;

    __kernel_rodata_start = .;
    .rodata ALIGN(4K) : AT (ADDR(.rodata) - KERNEL_VADDR_BASE) {
        *(.rodata .rodata.*)
    }
    . = ALIGN(4K);
    __kernel_rodata_end = .;

    __kernel_data_start = .;
    .data ALIGN(4K) : AT (ADDR(.data) - KERNEL_VADDR_BASE) {
        *(.data .data.*)
        *(.ldata)
    }
    . = ALIGN(4K);
    __kernel_data_end = .;

    __kernel_bss_start = .;
    .bss ALIGN(4K) : AT (ADDR(.bss) - KERNEL_VADDR_BASE) {
        *(COMMON)
        *(.bss .bss.*)
        *(.lbss)
    }
    . = ALIGN(4K);
    __kernel_bss_end = .;

}