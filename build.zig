const std = @import("std");
const fmt = std.fmt;

const examples: []const []const u8 = &.{
    "simple",
    "settings",
    "eval-realise",
    "derivation",
    "closure",
    "string-context",
    "flake",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zignix_mod = b.addModule("zignix", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zignix_mod.linkSystemLibrary("nix-expr-c", .{});
    zignix_mod.linkSystemLibrary("nix-fetchers-c", .{});
    zignix_mod.linkSystemLibrary("nix-flake-c", .{});
    zignix_mod.linkSystemLibrary("nix-store-c", .{});
    zignix_mod.linkSystemLibrary("nix-util-c", .{});

    const zignix_lib = b.addLibrary(.{
        .name = "zignix",
        .root_module = zignix_mod,
        .linkage = .static,
    });
    b.installArtifact(zignix_lib);

    for (examples) |name| {
        try buildExample(b, .{
            .name = name,
            .target = target,
            .optimize = optimize,
            .zignix = zignix_mod,
        });
    }

    const zignix_tests = b.addTest(.{
        .root_module = zignix_mod,
    });
    const test_artifact = b.addRunArtifact(zignix_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);

    const docs_step = b.step("docs", "Build zignix library docs");
    const docs = zignix_lib.getEmittedDocs();
    docs_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);
}

const BuildExampleOptions = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zignix: *std.Build.Module,
};

fn buildExample(b: *std.Build, options: BuildExampleOptions) !void {
    const root_source_file = try fmt.allocPrint(b.allocator, "example/{s}.zig", .{options.name});
    const exec_name = try fmt.allocPrint(b.allocator, "example-{s}", .{options.name});

    const mod = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = options.target,
        .optimize = options.optimize,
    });
    mod.addImport("zignix", options.zignix);

    const exe = b.addExecutable(.{
        .name = exec_name,
        .root_module = mod,
    });
    b.installArtifact(exe);
}
