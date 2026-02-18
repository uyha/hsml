pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests");

    const root_mod = b.addModule("hsml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const root_test = b.addTest(.{
        .name = "hsml",
        .root_module = root_mod,
    });
    const root_test_run = b.addRunArtifact(root_test);
    test_step.dependOn(&root_test_run.step);

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("hsml", root_mod);
    const main_exe = b.addExecutable(.{
        .name = "main",
        .root_module = main_mod,
    });
    const main_run = b.addRunArtifact(main_exe);
    const main_step = b.step("main", "Run main");
    main_step.dependOn(&main_run.step);

    b.installArtifact(main_exe);

    if (b.args) |args| {
        main_run.addArgs(args);
    }

    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    const example_exe = b.addExecutable(.{
        .name = "simple",
        .root_module = example_mod,
    });
    const example_run = b.addRunArtifact(example_exe);
    const example_step = b.step("simple", "Run simple example");
    example_step.dependOn(&example_run.step);

    b.installArtifact(example_exe);
}

const std = @import("std");
