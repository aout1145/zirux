const std = @import("std");
const uefi = std.os.uefi;
const utf16 = std.unicode.utf8ToUtf16LeStringLiteral;

const config: struct {
    kernel_path: []const u8,
} = @import("config.zon");

fn println(comptime str: []const u8) void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.outputString(utf16(str ++ "\r\n")) catch {};
}

pub fn main() uefi.Error!void {
    println("loader: Starting...");
    errdefer |e| switch (e) {
        inline else => |err| {
            @panic(@errorName(err));
        },
    };
    const header = try loadKernel();
    try bootKernel(header);
}

const ProgramHeaderIterator = struct {
    elf_header: std.elf.Header,
    file: *uefi.protocol.File,
    index: usize = 0,
    pub fn init(elf_header: std.elf.Header, file: *uefi.protocol.File) @This() {
        return .{ .elf_header = elf_header, .file = file };
    }
    /// support 64-bit only
    pub fn next(it: *@This()) !?std.elf.Elf64_Phdr {
        if (it.index >= it.elf_header.phnum) return null;
        defer it.index += 1;

        const size: u64 = @sizeOf(std.elf.Elf64_Phdr);
        const offset = it.elf_header.phoff + size * it.index;
        try it.file.setPosition(offset);

        var phdr: std.elf.Elf64_Phdr = undefined;
        const buffer: [*]u8 = @ptrCast(&phdr);
        _ = try it.file.read(buffer[0..size]);
        return phdr;
    }
};

fn loadKernel() !std.elf.Header {
    println("loader: Loading " ++ config.kernel_path ++ "...");
    const bs = uefi.system_table.boot_services.?;

    // open file
    const loaded_image_protocol = (try bs.handleProtocol(
        uefi.protocol.LoadedImage,
        uefi.handle,
    )).?;
    const fs = (try bs.handleProtocol(
        uefi.protocol.SimpleFileSystem,
        loaded_image_protocol.device_handle.?,
    )).?;
    const rootfs = try fs.openVolume();
    defer rootfs.close() catch {};
    const file = try rootfs.open(utf16(config.kernel_path), .read, .{});
    defer file.close() catch {};

    // read header
    const header_size = @sizeOf(std.elf.Elf64_Ehdr);
    const header_buffer = try bs.allocatePool(.boot_services_data, header_size);
    defer bs.freePool(header_buffer.ptr) catch {};
    const header_read_size = try file.read(header_buffer);
    var header_reader = std.Io.Reader.fixed(header_buffer[0..header_read_size]);
    const header = try std.elf.Header.read(&header_reader);

    // calculate pages
    const Addr = std.elf.Elf64_Addr;
    var kernel_start_phys: Addr = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;
    var iter = ProgramHeaderIterator.init(header, file);
    while (try iter.next()) |phdr| if (phdr.p_type == std.elf.PT_LOAD) {
        kernel_start_phys = @min(kernel_start_phys, phdr.p_paddr);
        kernel_end_phys = @max(kernel_end_phys, phdr.p_paddr + phdr.p_memsz);
    };
    const pages_4kib = (kernel_end_phys - kernel_start_phys + (4096 - 1)) / 4096;

    // allocate pages
    _ = try bs.allocatePages(
        .{ .address = @ptrFromInt(kernel_start_phys) },
        .loader_data,
        pages_4kib,
    );

    // load kernel
    iter = ProgramHeaderIterator.init(header, file);
    while (try iter.next()) |phdr| if (phdr.p_type == std.elf.PT_LOAD) {
        try file.setPosition(phdr.p_offset);
        const segment: [*]u8 = @ptrFromInt(phdr.p_paddr);
        const mem_size = phdr.p_memsz;
        _ = try file.read(segment[0..mem_size]);
        // init bss
        const zero_count = phdr.p_memsz - phdr.p_filesz;
        if (zero_count > 0) {
            const zero_ptr: [*]u8 = @ptrFromInt(phdr.p_paddr + phdr.p_filesz);
            @memset(zero_ptr[0..zero_count], 0);
        }
    };

    return header;
}

fn bootKernel(header: std.elf.Header) !noreturn {
    const defs = @import("loader-defs");
    const bs = uefi.system_table.boot_services.?;

    println("loader: Booting " ++ config.kernel_path ++ "...");

    const boot_info_buffer = try bs.allocatePool(.boot_services_data, @sizeOf(defs.BootInfo));
    const boot_info: *defs.BootInfo = @ptrCast(boot_info_buffer.ptr);
    boot_info.magic = defs.magic;
    boot_info.uefi_system_table_base = @intFromPtr(uefi.system_table);

    // graphics output info
    if (try bs.locateProtocol(uefi.protocol.GraphicsOutput, null)) |gop| {
        if (gop.queryMode(gop.mode.mode)) |info| {
            if (switch (info.pixel_format) {
                .red_green_blue_reserved_8_bit_per_color, .blue_green_red_reserved_8_bit_per_color => true,
                else => false,
            }) {
                boot_info.framebuffer_info = .{
                    .available = true,
                    .frame_buffer_base = gop.mode.frame_buffer_base,
                    .frame_buffer_size = gop.mode.frame_buffer_size,
                    .horizontal_resolution = info.horizontal_resolution,
                    .vertical_resolution = info.vertical_resolution,
                    .pixel_format = switch (info.pixel_format) {
                        .red_green_blue_reserved_8_bit_per_color => .rgb,
                        .blue_green_red_reserved_8_bit_per_color => .bgr,
                        else => unreachable,
                    },
                    .pixels_per_scan_line = info.pixels_per_scan_line,
                };
            }
        } else |_| {}
    }

    // {
    //     const map_info = try bs.getMemoryMapInfo();
    //     const map_size = (map_info.len + 2) * map_info.descriptor_size;
    //     const map_buffer = try bs.allocatePool(.boot_services_data, map_size);
    //     const map = try bs.getMemoryMap(map_buffer);
    //     var iter = map.iterator();
    //     while (iter.next()) |desc| {
    //         if (!desc.attribute.memory_runtime) continue;
    //         var buf: [256]u8 = undefined;
    //         const utf8str = try std.fmt.bufPrintZ(&buf, "{s} {s} 0x{x} {} \r\n", .{
    //             if (desc.attribute.memory_runtime) "RT" else "",
    //             @tagName(desc.type),
    //             desc.physical_start,
    //             desc.number_of_pages,
    //         });
    //         const con_out = uefi.system_table.con_out.?;
    //         var utf16str: [256]u16 = undefined;
    //         @memset(&utf16str, 0);
    //         _ = try std.unicode.utf8ToUtf16Le(&utf16str, utf8str);
    //         _ = con_out.outputString(@ptrCast(&utf16str)) catch {};
    //     }
    // }

    // memory map
    const map_info = try bs.getMemoryMapInfo();
    const map_size = (map_info.len + 2) * map_info.descriptor_size;
    const map_buffer = try bs.allocatePool(.boot_services_data, map_size);
    const map = try bs.getMemoryMap(map_buffer);
    boot_info.memory_map = .{
        .base = @intFromPtr(map.ptr),
        .len = map.info.len,
        .descriptor_size = map.info.descriptor_size,
        .descriptor_version = map.info.descriptor_version,
    };

    // exit boot services
    try bs.exitBootServices(uefi.handle, map.info.key);

    // jump to kernel
    const EntryFunc = fn (*defs.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn;
    const entry: *const EntryFunc = @ptrFromInt(header.entry);
    entry(boot_info);

    unreachable;
}
