const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");

const Allocator = @import("./Allocator.zig");
const metrics = @import("./metrics.zig");
const clock = @import("./clock.zig");

/// Private zenith data part of benchmark context.
const Private = struct {
    iter: usize,
    metrics: metrics.Bench,
    clock_prec: u64,

    fn init(self: *Private) !void {
        self.iter = 0;
        try self.metrics.init();
        self.clock_prec = clock.precision();
    }

    fn loop(self: *Private) bool {
        self.metrics.stop();
        if (self.iter > 0 and self.metrics.time.sample.ns > 120 * self.clock_prec)
            return false;
        self.iter += 1;
        self.metrics.start();
        return true;
    }
};

/// Context passed to micro benchmark functions.
pub const M = struct {
    /// Private field used by zenith.
    private: *const Private,

    /// Memory allocator.
    allocator: std.mem.Allocator,

    /// Loop returns true while benchmark function should iterate.
    ///
    /// ```zig
    /// fn myMicroBench(m: *const zenith.M) {
    ///     // setup my bench.
    ///     // ...
    ///
    ///     while (m.loop()) { // timer starts here.
    ///       // code to benchmark
    ///       // ....
    ///     } // timer ends here.
    ///
    ///     // cleanup my bench.
    ///     // ...
    /// }
    /// ```
    pub fn loop(self: *const M) bool {
        return @constCast(self.private).loop();
    }
};

/// A micro benchmark function that accepts a benchmarking context M.
pub const MicroBenchFn = fn (*const M) void;

/// Micro benchmark output.
pub const MicroBenchmark = struct {
    iter: usize,
    sample: metrics.Bench.Sample,
};

/// Measure the performance of `ubench_fn` function. Micro benchmark are
/// tailored to measure performance of single threaded code (no contention)
/// with an execution time in the range of few nanoseconds to hundred
/// milliseconds.
///
/// It takes into account the system clock precision and tries to minimize
/// interference from OS scheduling, context switches, CPU frequency scaling
/// and more.
///
/// This function samples `ubench_fn` many times and returns the minimum
/// execution time, that is, the sample with less delay introduced.
pub fn microBench(ubench_fn: MicroBenchFn) !MicroBenchmark {
    if (!options.run) return error.NoBench;
    if (builtin.mode == .Debug and !options.allow_debug)
        @compileError("you should not run benchmark on non optimized build (set allow_debug options to true)");

    var result: MicroBenchmark = .{
        .iter = std.math.maxInt(usize),
        .sample = metrics.Bench.Sample.max,
    };

    var total_duration_ns: usize = 0;
    var sample_count: usize = 0;

    while (sample_count < options.sample_count_min or
        ((total_duration_ns / std.time.ns_per_ms) < options.duration_ms_max and
            sample_count < (options.sample_count_max orelse std.math.maxInt(u32))))
    {
        var private: Private = undefined;
        try private.init();

        var alloc = Allocator.init(std.testing.allocator, &private.metrics.alloc);

        var m = M{
            .private = &private,
            .allocator = alloc.allocator(),
        };

        ubench_fn(&m);

        if (private.iter == 0) @panic("benchmark function never called loop()");

        const sample = private.metrics.sample();

        if (sample.time.ns < result.sample.time.ns) {
            result = .{ .sample = sample, .iter = private.iter };
        }

        try std.testing.expectEqual(.ok, std.testing.allocator_instance.deinit());

        sample_count += 1;
        total_duration_ns += result.sample.time.ns;
    }

    return result;
}
