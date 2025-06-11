const std = @import("std");

pub fn addIncludes(b: *std.Build, mod: anytype) !void {
    var environment = try std.process.getEnvMap(b.allocator);
    defer environment.deinit();

    if (environment.get("INCLUDE")) |val| {
        var iter = std.mem.splitAny(u8, val, ":");
        while (iter.next()) |include_path| {
            mod.addIncludePath(.{ .cwd_relative = include_path });
        }
    }
}

pub fn compileShaders(b: *std.Build, src: std.Build.LazyPath, comptime name: []const u8, mod: *std.Build.Module) void {
    const compute_command = b.addSystemCommand(&.{"slangc"});
    compute_command.addFileArg(src);
    compute_command.addArgs(&.{
        "-target", "spirv",
        "-entry",  "main",
    });
    const compute = compute_command.captureStdOut();

    const shader_command = b.addSystemCommand(&.{"./shaders/convert.sh"});
    shader_command.addFileArg(compute);
    const shader = shader_command.addOutputFileArg(name ++ ".zig");

    const shader_mod = b.addModule(name, .{
        .root_source_file = shader,
    });
    mod.addImport(name, shader_mod);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdl_c = b.addTranslateC(.{
        .root_source_file = b.path("src/sdl.h"),
        .target = target,
        .optimize = optimize,
    });

    try addIncludes(b, sdl_c);
    compileShaders(b, b.path("shaders/main.slang"), "shader", exe_mod);

    const sdl = sdl_c.createModule();
    exe_mod.linkSystemLibrary("SDL3", .{});
    exe_mod.addImport("sdl", sdl);

    const exe = b.addExecutable(.{
        .name = "Daedalus",
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

    const check = b.step("check", "Check if they compile");
    check.dependOn(&exe.step);
}
