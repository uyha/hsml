pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
