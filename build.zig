const std = @import("std");

pub const Options = struct {
    shared: bool = false,

    const defaults = Options{};

    pub fn getOptions(b: *std.Build) Options {
        return .{
            .shared = b.option(bool, "shared", "Compile as a shared library") orelse defaults.shared,
        };
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = Options.getOptions(b);

    const upstream = b.dependency("libplctag", .{});
    const lib = b.addLibrary(.{
        .name = "plctag",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/lib"),
        .files = &.{
            "init.c",
            "lib.c",
            "version.c",
        },
        .flags = &.{},
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
        .flags = &.{},
    });

    switch (target.result.os.tag) {
        .windows => {
            lib.linkSystemLibrary("ws2_32");
            lib.linkSystemLibrary("bcrypt");
            lib.addCSourceFiles(.{
                .root = upstream.path("src/platform/windows"),
                .files = &.{"platform.c"},
                .flags = &.{
                    "-DPLATFORM_WINDOWS=1",
                    "-DWIN32_LEAN_AND_MEAN",
                    "-D_CRT_SECURE_NO_WARNINGS",
                },
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
                .flags = &.{},
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
        .flags = &.{},
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
        .flags = &.{},
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
        .flags = &.{},
    });

    lib.addCSourceFiles(.{
        .root = upstream.path("src/libplctag/protocols/system"),
        .files = &.{"system.c"},
        .flags = &.{},
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

    const exe = b.addExecutable(.{
        .name = "simple",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = &.{
            "src/examples/simple.c",
        },
        .flags = &.{},
    });
    exe.root_module.addIncludePath(upstream.path("src"));
    exe.linkLibrary(lib);
    exe.linkLibC();

    const run_simple = b.addRunArtifact(exe);
    const run_step = b.step("run-simple", "Run the plctag simple example");
    run_step.dependOn(&run_simple.step);

    b.installArtifact(exe);
    b.installArtifact(lib);
}
