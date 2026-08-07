/// See also: https://wiki.osdev.org/CPU_Registers_x86-64#RFLAGS_Register
pub const Rflags = packed struct(u64) {
    /// Carry Flag
    cf: bool,
    _reserved1: u1,
    /// Parity Flag
    pf: bool,
    _reserved2: u1,
    /// Auxiliary Carry Flag
    af: bool,
    _reserved3: u1,
    /// Zero Flag
    zf: bool,
    /// Sign Flag
    sf: bool,
    /// Trap Flag
    tf: bool,
    /// Interrupt Enable Flag
    @"if": bool,
    /// Direction Flag
    df: bool,
    /// Overflow Flag
    of: bool,
    /// I/O Privilege Level
    iopl: u2,
    /// Nested Task
    nt: bool,
    _reserved4: u1,
    /// Resume Flag
    rf: bool,
    /// Virtual-8086 Mode
    vm: bool,
    /// Alignment Check / Access Control
    ac: bool,
    /// Virtual Interrupt Flag
    vif: bool,
    /// Virtual Interrupt Pending
    vip: bool,
    /// ID Flag
    id: bool,
    _reserved5: u42,
};

/// See also: https://wiki.osdev.org/CPU_Registers_x86-64#CR3
pub const Cr3 = packed struct(u64) {
    _reserved: u12,
    /// Physical Base Address of the PML4 (Bit 12-63)
    phys: u52,
};

/// See also: https://wiki.osdev.org/CPU_Registers_x86-64#CR4
pub const Cr4 = packed struct(u64) {
    /// Virtual 8086 Mode Extensions
    vme: bool,
    /// Protected-mode Virtual Interrupts
    pvi: bool,
    /// Time Stamp enabled only in ring 0
    tsd: bool,
    /// Debugging Extensions
    de: bool,
    /// Page Size Extension
    pse: bool,
    /// Physical Address Extension
    pae: bool,
    /// Machine Check Exception
    mce: bool,
    /// Page Global Enable
    pge: bool,
    /// Performance Monitoring Counter Enable
    pce: bool,
    /// Operating system support for FXSAVE and FXRSTOR instructions
    osfxsr: bool,
    /// Operating System Support for Unmasked SIMD Floating-Point Exceptions
    osxmmexcpt: bool,
    /// User-Mode Instruction Prevention (SGDT, SIDT, SLDT, SMSW, and STR are disabled in user mode)
    umip: bool,
    /// 5-Level Paging
    la57: bool,
    /// Virtual Machine Extensions Enable
    vmxe: bool,
    /// Safer Mode Extensions Enable
    smxe: bool,
    /// Reserved
    _reserved1: u1,
    /// Enables the instructions RDFSBASE, RDGSBASE, WRFSBASE, and WRGSBASE
    fsgsbase: bool,
    /// PCID Enable
    pcide: bool,
    /// XSAVE and Processor Extended States Enable
    osxsave: bool,
    /// Reserved
    _reserved2: u1,
    /// Supervisor Mode Execution Protection Enable
    smep: bool,
    /// Supervisor Mode Access Prevention Enable
    smap: bool,
    /// Protection Key Enable
    pke: bool,
    /// Control-flow Enforcement Technology
    cet: bool,
    /// Enable protection keys for supervisor-mode pages
    pks: bool,
    /// Reserved
    _reserved3: u39,
};

/// See also: https://wiki.osdev.org/CPU_Registers_x86-64#IA32_EFER
pub const Efer = packed struct(u64) {
    pub const msr = 0xC0000080;

    /// SYSCALL Enable
    sce: bool,
    _reserved1: u7,
    /// IA-32e Mode Enable
    lme: bool,
    _reserved2: u1,
    /// IA-32e Mode Active
    lma: bool,
    /// Execute Disable Bit Enable
    nxe: bool,
    _reserved3: u52,
};

pub const FsBase = packed struct(u64) {
    pub const msr = 0xC0000100;

    fs_base: u64,
};
pub const GsBase = packed struct(u64) {
    pub const msr = 0xC0000101;

    gs_base: u64,
};
pub const KernelGsBase = packed struct(u64) {
    pub const msr = 0xC0000102;

    kernel_gs_base: u64,
};

/// See also: https://wiki.osdev.org/SYSENTER#AMD:_SYSCALL/SYSRET
pub const Star = packed struct(u64) {
    const msr = 0xC0000081;

    _reserved: u32,
    /// kernel_cs = kernel_segments
    /// kernel_ss = kernel_segments + 8
    kernel_segments: u16,
    /// user_cs = user_segments + 16
    /// user_ss = user_segments + 8
    user_segments: u16,
};

/// See also: https://wiki.osdev.org/SYSENTER#AMD:_SYSCALL/SYSRET
pub const Lstar = packed struct(u64) {
    pub const msr = 0xC0000082;

    rip: u64,
};

/// See also: https://wiki.osdev.org/SYSENTER#AMD:_SYSCALL/SYSRET
pub const Fmask = packed struct(u64) {
    pub const msr = 0xC0000084;

    mask: Rflags,
};

/// See also: https://wiki.osdev.org/APIC
pub const ApicBase = packed struct(u64) {
    pub const msr = 0x1B;

    _reserved1: u8,
    /// Professor is BSP
    bsp: bool,
    _reserved2: u1,
    /// Enable x2APIC mode
    extd: bool,
    /// xAPIC global enable/disable
    en: bool,
    /// NOTE: DO NOT USE
    apic_base: u24,
    _reserved3: u28,
};

/// See also: https://wiki.osdev.org/X86_Paging#PAT
pub const Pat = packed struct(u64) {
    pub const msr = 0x277;

    pat: u64,
};
