const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zignix", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "zignix",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_artifact = b.addRunArtifact(tests);

    tests.linkLibC();
    tests.linkSystemLibrary("nixexprc");
    tests.linkSystemLibrary("nixstorec");
    tests.linkSystemLibrary("nixutilc");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
