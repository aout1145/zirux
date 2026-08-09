KERNEL_PADDR_TEXT = 0x0000000000200000;
KERNEL_VADDR_BASE = 0xFFFFFFFF80000000;
KERNEL_VADDR_TEXT = 0xFFFFFFFF80200000;

SECTIONS {
    . = KERNEL_PADDR_TEXT;

    __kernel_boot_start = . + KERNEL_VADDR_BASE;
    .boot ALIGN(4K) : {
        *(.boot)
    }
    . = ALIGN(4K);
    __kernel_boot_end = . + KERNEL_VADDR_BASE;

    __kernel_per_cpu_start = . + KERNEL_VADDR_BASE;
    .per_cpu ALIGN(4K) : {
        *(.per_cpu)
    }
    . = ALIGN(4K);
    __kernel_per_cpu_end = . + KERNEL_VADDR_BASE;

    . = KERNEL_VADDR_TEXT + SIZEOF(.boot) + SIZEOF(.per_cpu);
    . = ALIGN(4K);

    __kernel_init_start = .;
    .init ALIGN(4K) : AT (ADDR(.init) - KERNEL_VADDR_BASE) {
        *(.init)
    }
    . = ALIGN(4K);
    __kernel_init_end = .;

    __kernel_text_start = .;
    .text ALIGN(4K) : AT (ADDR(.text) - KERNEL_VADDR_BASE) {
        *(.text)
        *(.ltext)
    }
    . = ALIGN(4K);
    __kernel_text_end = .;

    __kernel_rodata_start = .;
    .rodata ALIGN(4K) : AT (ADDR(.rodata) - KERNEL_VADDR_BASE) {
        *(.rodata)
    }
    . = ALIGN(4K);
    __kernel_rodata_end = .;

    __kernel_data_start = .;
    .data ALIGN(4K) : AT (ADDR(.data) - KERNEL_VADDR_BASE) {
        *(.data)
        *(.ldata)
    }
    . = ALIGN(4K);
    __kernel_data_end = .;

    __kernel_bss_start = .;
    .bss ALIGN(4K) : AT (ADDR(.bss) - KERNEL_VADDR_BASE) {
        *(COMMON)
        *(.bss)
        *(.lbss)
    }
    . = ALIGN(4K);
    __kernel_bss_end = .;

}