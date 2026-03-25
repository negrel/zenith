const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run = b.option(bool, "run", "Run benchmarks") orelse false;
    const allow_debug = b.option(bool, "allow_debug", "Allow benchmark to run in debug mode") orelse false;
    const sample_count_min = b.option(
        u32,
        "sample_count_min",
        "Minimum number of samples per benchmark",
    ) orelse 1;
    const sample_count_max = b.option(
        u32,
        "sample_count_max",
        "Maximum number of samples per benchmark",
    );
    const duration_ms_max = b.option(
        u64,
        "duration_ms_max",
        "Maximum duration of a benchmark",
    ) orelse std.time.ms_per_s;

    const mod = b.addModule("zenith", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zenith",
        .linkage = .static,
        .root_module = mod,
    });

    const options = b.addOptions();
    options.addOption(bool, "run", run);
    options.addOption(bool, "allow_debug", allow_debug);
    options.addOption(u32, "sample_count_min", sample_count_min);
    options.addOption(?u32, "sample_count_max", sample_count_max);
    options.addOption(u64, "duration_ms_max", duration_ms_max);
    lib.root_module.addOptions("options", options);

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_unit_tests.root_module.addOptions("options", options);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const install_lib_unit_tests = b.addInstallArtifact(lib_unit_tests, .{});

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&install_lib_unit_tests.step);

    // Generate documentation.
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install docs into zig-out/docs");
    docs_step.dependOn(&install_docs.step);
}
