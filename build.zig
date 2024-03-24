const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zignix", .{
        .source_file = .{ .path = "src/lib.zig" },
    });

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    const test_artifact = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
