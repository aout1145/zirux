const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const loader_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });
    const exe_loader = b.addExecutable(.{
        .name = "bootx64.efi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/x86_64/main.zig"),
            .target = loader_target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "loader-defs",
                    .module = b.createModule(.{
                        .root_source_file = b.path("src/kernel/arch/x86_64/boot/defs.zig"),
                    }),
                },
            },
        }),
        .linkage = .static,
    });
    b.installArtifact(exe_loader);

    const init_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
    });
    const exe_init = b.addExecutable(.{
        .name = "init.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/init/main.zig"),
            .target = init_target,
            .optimize = optimize,
        }),
        .linkage = .static,
        .use_llvm = true,
        .use_lld = true,
    });
    b.installArtifact(exe_init);

    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .ofmt = .elf,
        .cpu_features_add = std.Target.x86.featureSet(&.{.soft_float}),
        .cpu_features_sub = std.Target.x86.featureSet(&.{
            .mmx,
            .sse,
            .sse2,
        }),
    });
    const exe_kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel/root.zig"),
            .target = kernel_target,
            .optimize = optimize,
            .code_model = .kernel,
            .red_zone = false,
        }),
        .linkage = .static,
        .use_llvm = true,
        .use_lld = true,
    });
    exe_kernel.root_module.addAssemblyFile(b.path("src/kernel/arch/x86_64/boot/trampoline.S"));
    exe_kernel.root_module.addAnonymousImport(
        "init_elf",
        .{ .root_source_file = exe_init.getEmittedBin() },
    );
    exe_kernel.setLinkerScript(b.path("src/kernel/arch/x86_64/linker.lds"));
    b.installArtifact(exe_kernel);

    const out_dir_name = "img";
    const install_loader = b.addInstallFile(
        exe_loader.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, exe_loader.name }),
    );
    install_loader.step.dependOn(&exe_loader.step);
    b.getInstallStep().dependOn(&install_loader.step);
    const install_kernel = b.addInstallFile(
        exe_kernel.getEmittedBin(),
        b.fmt("{s}/{s}", .{ out_dir_name, exe_kernel.name }),
    );
    install_kernel.step.dependOn(&exe_kernel.step);
    b.getInstallStep().dependOn(&install_kernel.step);

    const qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "8G",
        "-bios",
        "/usr/share/ovmf/x64/OVMF.4m.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, out_dir_name }),
        // "-nographic",
        "-display",
        "sdl,gl=on",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        // "-no-shutdown",
        "-enable-kvm",
        "-cpu",
        "host",
        "-smp",
        "8",
        "-s",
        // "-S",
    };
    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());
    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}
