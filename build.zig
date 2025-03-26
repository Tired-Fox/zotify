const std = @import("std");

const examples = [_]Example {
    .{ .name = "basic-refresh", .path = "examples/basic_refresh.zig",  },
};

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

    inline for (examples) |example| {
        addExample(b, target, optimize, example, &[_]ModuleMap{
            .{ "zotify", module }
        });
    }
}

const ModuleMap = std.meta.Tuple(&[_]type{ []const u8, *std.Build.Module });
const Example = struct {
    name: []const u8,
    path: []const u8,
};

pub fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime example: Example,
    modules: []const ModuleMap,
) void {
    const exe = b.addExecutable(.{
        .name = example.name,
        .root_source_file = b.path(example.path),
        .target = target,
        .optimize = optimize,
    });

    for (modules) |module| {
        exe.root_module.addImport(module[0], module[1]);
    }

    const ecmd = b.addRunArtifact(exe);
    ecmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        ecmd.addArgs(args);
    }

    const estep = b.step("example-" ++ example.name, "Run example-" ++ example.name);
    estep.dependOn(&ecmd.step);
}
