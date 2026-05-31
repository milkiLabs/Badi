const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_name = "badi";

    const qt6_extra_path = b.option([]const u8, "qt6-extra-path", "Qt6 header search path") orelse "";
    const qt6_paths: []const []const u8 = if (qt6_extra_path.len > 0) &.{qt6_extra_path} else &.{};
    const qt6lib_path = b.option([]const u8, "qt6-lib-path", "Qt6 library search path") orelse "";

    const qt6zig = b.dependency("libqt6zig", .{
        .target = target,
        .optimize = .ReleaseFast,
        .@"extra-paths" = qt6_paths,
    });

    const exe = b.addExecutable(.{
        .name = app_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("libqt6zig", qt6zig.module("libqt6zig"));
    exe.root_module.linkSystemLibrary("Qt6Core", .{});
    exe.root_module.linkSystemLibrary("Qt6Gui", .{});
    exe.root_module.linkSystemLibrary("Qt6Widgets", .{});

    // libqt6zig currently adds libc++ linkage, but the generated Qt wrappers use
    // libstdc++ symbols on Linux. Add the concrete libstdc++.so to avoid link
    // order/toolchain mismatches.
    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = &.{ "gcc", "--print-file-name=libstdc++.so.6" },
    }) catch @panic("failed to run gcc");
    exe.root_module.addObjectFile(.{
        .cwd_relative = std.mem.trim(u8, result.stdout, &std.ascii.whitespace),
    });
    exe.root_module.linkSystemLibrary("unwind", .{});

    if (qt6lib_path.len > 0)
        exe.root_module.addLibraryPath(.{ .cwd_relative = qt6lib_path });

    // Link the libqt6zig static libraries
    const qtlibs = &[_][]const u8{
        "qabstractbutton",
        "qabstractitemmodel",
        "qabstractitemview",
        "qapplication",
        "qboxlayout",
        "qcoreevent",
        "qevent",
        "qlabel",
        "qlayout",
        "qlineedit",
        "qlistview",
        "qprocess",
        "qsocketnotifier",
        "qvariant",
        "qwidget",
    };
    for (qtlibs) |lib|
        exe.root_module.linkLibrary(qt6zig.artifact(lib));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const core_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
