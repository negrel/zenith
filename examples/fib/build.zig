const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const bench = b.option(bool, "bench", "Run zenith benchmarks") orelse false;

    const mod = b.addModule("fib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    run_mod_tests.has_side_effects = bench;

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    if (b.lazyDependency("zenith", .{
        .target = target,
        .optimize = optimize,
        .run = bench,
    })) |dep| {
        mod_tests.root_module.addImport("zenith", dep.module("zenith"));
        const install = b.addInstallArtifact(mod_tests, .{});
        test_step.dependOn(&install.step);
    }
}
