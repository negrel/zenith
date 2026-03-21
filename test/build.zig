const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench = b.option(bool, "bench", "Run zenith benchmarks") orelse false;

    const mod = b.addModule("test", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zenith = b.dependency("zenith", .{
        .run = bench,
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("zenith", zenith.module("zenith"));

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
