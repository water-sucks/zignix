const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zignix_mod = b.addModule("zignix", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zignix_lib = b.addStaticLibrary(.{
        .name = "zignix",
        .root_module = zignix_mod,
    });
    b.installArtifact(zignix_lib);

    const example_mod = b.createModule(.{
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("zignix", zignix_mod);
    const example_exe = b.addExecutable(.{
        .name = "zignix-example",
        .root_module = example_mod,
    });
    b.installArtifact(example_exe);

    example_exe.linkLibC();
    example_exe.linkSystemLibrary("nix-expr-c");
    example_exe.linkSystemLibrary("nix-store-c");
    example_exe.linkSystemLibrary("nix-util-c");

    const zignix_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_artifact = b.addRunArtifact(zignix_tests);

    zignix_tests.linkLibC();
    zignix_tests.linkSystemLibrary("nix-expr-c");
    zignix_tests.linkSystemLibrary("nix-store-c");
    zignix_tests.linkSystemLibrary("nix-util-c");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
