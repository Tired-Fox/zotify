const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const open = b.dependency("zig_open", .{}).module("open");
    const dotenvy = b.dependency("dotenvy", .{}).module("dotenvy");
    const known_folders = b.dependency("known_folders", .{}).module("known-folders");

    const module = b.addModule("zotify", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("open", open);
    module.addImport("dotenvy", dotenvy);
    module.addImport("known-folders", known_folders);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("open", open);
    exe_mod.addImport("dotenvy", dotenvy);
    exe_mod.addImport("known-folders", known_folders);
    exe_mod.addImport("zotify", module);

    const exe = b.addExecutable(.{
        .name = "zotify",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
