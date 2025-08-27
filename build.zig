const std = @import("std");

const LinkChoice = enum { static, shared, both };

pub const Options = struct {
    linkage: LinkChoice = .both,
    build_examples: bool = false,
    build_ab_server: bool = false,
    build_modbus_server: bool = false,

    const defaults = Options{};

    pub fn getOptions(b: *std.Build) Options {
        return .{
            .linkage = b.option(LinkChoice, "linkage", "Choose linkage: static|shared|both") orelse defaults.linkage,
            .build_examples = b.option(bool, "build-examples", "Build examples") orelse defaults.build_examples,
            .build_ab_server = b.option(bool, "build-ab-server", "Build AB server") orelse defaults.build_ab_server,
            .build_modbus_server = b.option(bool, "build-modbus-server", "Build MODBUS server") orelse defaults.build_modbus_server,
        };
    }
};

fn make_shims_dir(b: *std.Build) std.Build.LazyPath {
    const shims = b.addWriteFiles();
    // Case-fix shims so capitalized includes resolve on case-sensitive hosts.
    _ = shims.add("Windows.h",
        \\#include <windows.h>
    );
    _ = shims.add("Winsock2.h",
        \\#include <winsock2.h>
    );
    _ = shims.add("WinSock2.h",
        \\#include <winsock2.h>
    );
    _ = shims.add("Ws2tcpip.h",
        \\#include <ws2tcpip.h>
    );
    _ = shims.add("WS2tcpip.h",
        \\#include <ws2tcpip.h>
    );
    return shims.getDirectory();
}

fn make_c_flags(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !std.ArrayList([]const u8) {
    var c_flags: std.ArrayList([]const u8) = .empty;

    try c_flags.appendSlice(b.allocator, &[_][]const u8{"-std=c11"});
    if (target.result.os.tag == .windows) {
        switch (target.result.abi) {
            .gnu => try c_flags.appendSlice(b.allocator, &[_][]const u8{"-DMINGW=1"}),
            .msvc => try c_flags.appendSlice(b.allocator, &[_][]const u8{
                "-DPLATFORM_WINDOWS=1",
                "-DWIN32_LEAN_AND_MEAN",
                "-D_CRT_SECURE_NO_WARNINGS",
            }),
            else => @panic("Unusupported windows abi"),
        }
    } else {
        try c_flags.appendSlice(b.allocator, &[_][]const u8{ "-Wall", "-pedantic", "-Wextra", "-Wconversion", "-fno-strict-aliasing", "-fvisibility=hidden" });
    }

    switch (optimize) {
        .Debug => {},
        .ReleaseSmall, .ReleaseFast, .ReleaseSafe => {
            try c_flags.appendSlice(b.allocator, &[_][]const u8{"-DNDEBUG"});
        },
    }
    return c_flags;
}

fn make_lib(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, linkage: std.builtin.LinkMode, shims_dir: ?std.Build.LazyPath, c_flags: std.ArrayList([]const u8)) !*std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .name = "plctag",
        .linkage = linkage,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    if (shims_dir) |sd| {
        lib.root_module.addIncludePath(sd);
    }

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/lib"),
        .files = &.{
            "init.c",
            "lib.c",
            "version.c",
        },
        .flags = c_flags.items,
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/utils"),
        .files = &.{
            "atomic_utils.c",
            "attr.c",
            "debug.c",
            "hash.c",
            "hashtable.c",
            "random_utils.c",
            "rc.c",
            "vector.c",
        },
        .flags = c_flags.items,
    });

    switch (target.result.os.tag) {
        .windows => {
            if (target.result.abi == .gnu) {
                lib.linkSystemLibrary("ws2_32");
                lib.linkSystemLibrary("bcrypt");
            } else {
                lib.linkSystemLibrary("Ws2_32");
                lib.linkSystemLibrary("Bcrypt");
            }
            lib.addCSourceFiles(.{
                .root = upstream.path("src/platform/windows"),
                .files = &.{"platform.c"},
                .flags = c_flags.items,
            });
            lib.root_module.addIncludePath(upstream.path("src/platform/windows"));
        },
        else => {
            lib.linkSystemLibrary("pthread");
            lib.root_module.addCMacro("__USE_POSIX", "1");
            lib.root_module.addCMacro("_XOPEN_SOURCE", "700");
            lib.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
            lib.addCSourceFiles(.{
                .root = upstream.path("src/platform/posix"),
                .files = &.{"platform.c"},
                .flags = c_flags.items,
            });
            lib.root_module.addIncludePath(upstream.path("src/platform/posix"));
        },
    }
    if (target.result.os.tag == .macos) {
        lib.root_module.addCMacro("_DARWIN_C_SOURCE", "null");
    }

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/mb"),
        .files = &.{"modbus.c"},
        .flags = c_flags.items,
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/ab"),
        .files = &.{
            "ab_common.c",
            "cip.c",
            "eip_cip.c",
            "eip_cip_special.c",
            "eip_lgx_pccc.c",
            "eip_plc5_dhp.c",
            "eip_plc5_pccc.c",
            "eip_slc_dhp.c",
            "eip_slc_pccc.c",
            "error_codes.c",
            "pccc.c",
            "session.c",
        },
        .flags = c_flags.items,
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/omron"),
        .files = &.{
            "cip.c",
            "conn.c",
            "omron_common.c",
            "omron_raw_tag.c",
            "omron_standard_tag.c",
        },
        .flags = c_flags.items,
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/system"),
        .files = &.{"system.c"},
        .flags = c_flags.items,
    });

    lib.root_module.addIncludePath(upstream.path("src"));
    lib.root_module.addIncludePath(upstream.path("src/utils"));
    lib.root_module.addIncludePath(upstream.path("src/libplctag/protocols/mb"));
    lib.root_module.addIncludePath(upstream.path("src/libplctag/protocols/ab"));
    lib.root_module.addIncludePath(upstream.path("src/libplctag/protocols/omron"));
    lib.root_module.addIncludePath(upstream.path("src/libplctag/protocols/system"));

    lib.installHeadersDirectory(upstream.path("src/libplctag/lib"), "", .{
        .include_extensions = &.{
            "libplctag.h",
        },
    });
    return lib;
}

fn make_exe(b: *std.Build, name: []const u8, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shims_dir: ?std.Build.LazyPath, lib: *std.Build.Step.Compile, c_flags: std.ArrayList([]const u8)) !*std.Build.Step.Compile {
    const file = try std.fmt.allocPrint(b.allocator, "{s}.c", .{name});
    defer b.allocator.free(file);
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    if (shims_dir) |sd| {
        exe.root_module.addIncludePath(sd);
    }
    exe.addCSourceFiles(.{
        .root = upstream.path("src/examples"),
        .files = &.{
            file,
            "compat_utils.c",
        },
        .flags = c_flags.items,
    });
    switch (target.result.os.tag) {
        .windows => {},
        else => {
            exe.root_module.addCMacro("__USE_POSIX", "1");
            exe.root_module.addCMacro("_XOPEN_SOURCE", "700");
            exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
        },
    }
    if (target.result.os.tag == .macos) {
        lib.root_module.addCMacro("_DARWIN_C_SOURCE", "null");
    }
    exe.root_module.addIncludePath(upstream.path("src"));
    exe.root_module.addIncludePath(upstream.path("src/examples"));
    exe.linkLibC();
    exe.linkLibrary(lib);

    return exe;
}

fn make_examples(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shims_dir: ?std.Build.LazyPath, lib: *std.Build.Step.Compile, c_flags: std.ArrayList([]const u8)) !void {
    if (target.result.os.tag != .windows) {
        const examples: []const []const u8 = &[_][]const u8{
            "async",
            "async_stress",
            "barcode_test",
            "busy_test",
            "data_dumper",
            "list_tags_logix",
            "list_tags_micro8x0",
            "list_tags_omron_incomplete",
            "multithread",
            "multithread_cached_read",
            "multithread_plc5",
            "multithread_plc5_dhp",
            "plc5",
            "simple",
            // "simple_cpp.c",
            "simple_dual",
            "slc500",
            "stress_api_lock",
            "stress_rc_mem",
            "stress_test",
            "string_non_standard_udt",
            "string_standard",
            "test_alternate_tag_listing",
            "test_array_notation",
            "test_auto_sync",
            "test_reconnect_after_outage",
            "test_callback",
            "test_callback_ex",
            "test_callback_ex_logix",
            "test_callback_ex_modbus",
            "test_connection_group",
            "test_emulator_performance",
            "test_event",
            "test_indexed_tags",
            "test_raw_cip",
            "test_reconnect",
            "test_shutdown",
            "test_special",
            "test_string",
            "test_tag_attributes",
            "test_tag_type_attribute",
            "thread_stress",
            "toggle_bit",
            "toggle_bool",
            "trigger_double_free",
            "write_string",
            "tag_rw_deprecated",
            "tag_rw2",
        };
        for (examples) |exe_file| {
            const exe = try make_exe(
                b,
                exe_file,
                upstream,
                target,
                optimize,
                shims_dir,
                lib,
                c_flags,
            );
            b.installArtifact(exe);
        }
    } else {
        const examples: []const []const u8 = &[_][]const u8{
            "async",
            "async_stress",
            "barcode_test",
            "busy_test",
            // "data_dumper",
            "list_tags_logix",
            "list_tags_micro8x0",
            "list_tags_omron_incomplete",
            // "multithread",
            // "multithread_cached_read",
            // "multithread_plc5",
            // "multithread_plc5_dhp",
            "plc5",
            "simple",
            // "simple_cpp.c",
            "simple_dual",
            "slc500",
            "stress_api_lock",
            "stress_rc_mem",
            // "stress_test",
            "string_non_standard_udt",
            "string_standard",
            "test_alternate_tag_listing",
            "test_array_notation",
            "test_auto_sync",
            "test_reconnect_after_outage",
            "test_callback",
            "test_callback_ex",
            "test_callback_ex_logix",
            "test_callback_ex_modbus",
            "test_connection_group",
            "test_emulator_performance",
            "test_event",
            "test_indexed_tags",
            "test_raw_cip",
            "test_reconnect",
            "test_shutdown",
            "test_special",
            "test_string",
            "test_tag_attributes",
            "test_tag_type_attribute",
            "thread_stress",
            "toggle_bit",
            "toggle_bool",
            "trigger_double_free",
            "write_string",
            "tag_rw_deprecated",
            "tag_rw2",
        };
        for (examples) |exe_file| {
            const exe = try make_exe(
                b,
                exe_file,
                upstream,
                target,
                optimize,
                shims_dir,
                lib,
                c_flags,
            );
            b.installArtifact(exe);
        }
    }
}

fn make_ab_server(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shims_dir: ?std.Build.LazyPath, c_flags: std.ArrayList([]const u8)) !void {
    const exe = b.addExecutable(.{
        .name = "ab_server",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    if (shims_dir) |sd| {
        exe.root_module.addIncludePath(sd);
    }
    exe.addCSourceFiles(.{
        .root = upstream.path("src/tests/ab_server/src"),
        .files = &.{
            "cip.c",
            "cpf.c",
            "eip.c",
            "main.c",
            "memory.c",
            "mutex.c",
            "pccc.c",
            "socket.c",
            "tcp_server.c",
            "thread.c",
            "utils.c",
        },
        .flags = c_flags.items,
    });
    exe.root_module.addIncludePath(upstream.path("src/tests/ab_server/src"));
    exe.root_module.addIncludePath(upstream.path("src/utils"));
    exe.root_module.addIncludePath(upstream.path("src"));
    switch (target.result.os.tag) {
        .windows => {
            if (target.result.abi == .gnu) {
                exe.linkSystemLibrary("ws2_32");
                exe.linkSystemLibrary("bcrypt");
            } else {
                exe.linkSystemLibrary("Ws2_32");
                exe.linkSystemLibrary("Bcrypt");
            }
            exe.root_module.addIncludePath(upstream.path("src/platform/windows"));
        },
        else => {
            exe.root_module.addIncludePath(upstream.path("src/platform/posix"));
            exe.root_module.addCMacro("__USE_POSIX", "1");
            exe.root_module.addCMacro("_XOPEN_SOURCE", "700");
            exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
        },
    }
    if (target.result.os.tag == .macos) {
        exe.root_module.addCMacro("_DARWIN_C_SOURCE", "null");
    }
    exe.linkLibC();

    b.installArtifact(exe);
}

fn make_modbus_server(b: *std.Build, upstream: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shims_dir: ?std.Build.LazyPath, c_flags: std.ArrayList([]const u8)) !void {
    const exe = b.addExecutable(.{
        .name = "modbus_server",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    if (shims_dir) |sd| {
        exe.root_module.addIncludePath(sd);
    }
    exe.addCSourceFiles(.{
        .root = upstream.path("src/tests/modbus_server"),
        .files = &.{"modbus_server.c"},
        .flags = c_flags.items,
    });
    exe.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/mb"),
        .files = &.{"modbus.c"},
        .flags = c_flags.items,
    });
    exe.root_module.addIncludePath(upstream.path("src/libplctag/protocols/mb"));
    // exe.root_module.addIncludePath(upstream.path("src/utils"));
    exe.root_module.addIncludePath(upstream.path("src"));
    switch (target.result.os.tag) {
        .windows => {
            // if (target.result.abi == .gnu) {
            //     exe.linkSystemLibrary("ws2_32");
            //     exe.linkSystemLibrary("bcrypt");
            // } else {
            //     exe.linkSystemLibrary("Ws2_32");
            //     exe.linkSystemLibrary("Bcrypt");
            // }
            // exe.root_module.addIncludePath(upstream.path("src/platform/windows"));
        },
        else => {
            exe.root_module.addIncludePath(upstream.path("src/platform/posix"));
            exe.root_module.addCMacro("__USE_POSIX", "1");
            exe.root_module.addCMacro("_XOPEN_SOURCE", "700");
            exe.root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
        },
    }
    if (target.result.os.tag == .macos) {
        exe.root_module.addCMacro("_DARWIN_C_SOURCE", "null");
    }
    exe.linkLibC();
    exe.linkSystemLibrary("modbus");

    b.installArtifact(exe);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = Options.getOptions(b);

    const upstream = b.dependency("libplctag", .{});

    var shims_dir: ?std.Build.LazyPath = null;
    if (target.result.os.tag == .windows) {
        shims_dir = make_shims_dir(b);
    }

    var c_flags = try make_c_flags(b, target, optimize);
    defer c_flags.deinit(b.allocator);

    var lib_static: ?*std.Build.Step.Compile = null;
    var lib_shared: ?*std.Build.Step.Compile = null;
    switch (options.linkage) {
        .static => lib_static = try make_lib(b, upstream, target, optimize, .static, shims_dir, c_flags),
        .shared => lib_shared = try make_lib(b, upstream, target, optimize, .dynamic, shims_dir, c_flags),
        .both => {
            lib_static = try make_lib(b, upstream, target, optimize, .static, shims_dir, c_flags);
            lib_shared = try make_lib(b, upstream, target, optimize, .dynamic, shims_dir, c_flags);
        },
    }

    if (lib_static) |ls| {
        b.installArtifact(ls);
    }
    if (lib_shared) |ld| {
        b.installArtifact(ld);
    }

    if (options.build_examples) {
        try make_examples(b, upstream, target, optimize, shims_dir, lib_static orelse lib_shared.?, c_flags);
    }
    if (options.build_ab_server) {
        try make_ab_server(b, upstream, target, optimize, shims_dir, c_flags);
    }
    if (options.build_modbus_server and target.result.os.tag == .linux) {
        try make_modbus_server(b, upstream, target, optimize, shims_dir, c_flags);
    }
}
