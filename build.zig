const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run tests");

    const benchmarking = b.addModule("benchmarking", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/benchmarking/root.zig"),
    });

    const benchmarking_test = b.addTest(.{
        .root_module = benchmarking,
    });
    const run_benchmarking_test = b.addRunArtifact(benchmarking_test);
    test_step.dependOn(&run_benchmarking_test.step);

    const zenith_mod = b.addModule("zenith", .{
        .root_source_file = b.path("src/zenith/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zenith_mod.addImport("benchmarking", benchmarking);

    const zenith_exe = b.addExecutable(.{
        .name = "zenith",
        .root_module = zenith_mod,
    });
    b.installArtifact(zenith_exe);

    const zenith_test = b.addTest(.{ .root_module = zenith_mod });
    const run_zenith_test = b.addRunArtifact(zenith_test);
    test_step.dependOn(&run_zenith_test.step);

    const zenith_step = b.step("zenith", "Execute zenith CLI");
    const zenith_cmd = b.addRunArtifact(zenith_exe);
    zenith_step.dependOn(&zenith_cmd.step);
    zenith_cmd.addPassthruArgs();
}
