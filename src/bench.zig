const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");

const Allocator = @import("./Allocator.zig");
const metrics = @import("./metrics.zig");
const clock = @import("./clock.zig");
const HostInfo = @import("./HostInfo.zig");
const hint = @import("./hint.zig");

/// Private zenith data part of benchmark context.
const Private = struct {
    iter: usize,
    metrics: metrics.Bench,
    clock_prec_ns: u64,

    fn init(self: *Private) !void {
        self.iter = 0;
        try self.metrics.init();
        self.clock_prec_ns = clock.precision();
    }

    fn loop(self: *Private) bool {
        self.metrics.stop();
        if (self.iter > 0 and self.metrics.time.sample.ns > 100 * self.clock_prec_ns)
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

    /// Memory allocator that should be used by benchmarked code.
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
    clock_prec_ns: u64,
};

/// Measure the performance of `ubench_fn` function. Micro benchmark are
/// tailored to measure performance of single threaded code (no contention)
/// with an execution time in the range of few nanoseconds to hundred
/// milliseconds.
///
/// It takes into account the system clock.precision and tries to minimize
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
        .clock_prec_ns = clock.precision(),
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
            result = .{
                .sample = sample,
                .iter = private.iter,
                .clock_prec_ns = private.clock_prec_ns,
            };
        }

        try std.testing.expectEqual(.ok, std.testing.allocator_instance.deinit());

        sample_count += 1;
        total_duration_ns += result.sample.time.ns;
    }

    return result;
}

/// Micro benchmark all public function of type `MicroBenchFn` contained in
/// struct / namespace `T`.
///
/// Examples:
///
/// ```zig
/// try zenith.microBenchNamespace(@This());
///
/// try zenith.microBenchNamespace(struct {
///     fn myBench(m: *const zenith.M) void {
///         for (m.loop()) {
///             // Use black hole to prevent compiler from optimizing output of
///             // function.
///             // Use black box to prevent compiler from optimizing input of
///             // function.
///             zenith.blackHole(myFunc(zenith.blackBox(usize, &30)))
///         }
///     }
/// });
/// ```
pub fn microBenchNamespace(T: type) !void {
    const ti = @typeInfo(T).@"struct";

    var buf: [4096]u8 = undefined;
    var w = std.Progress.lockStderrWriter(buf[0..]);
    defer std.Progress.unlockStderrWriter();

    try HostInfo.init().print(w);

    inline for (ti.decls) |d| {
        const v = @field(T, d.name);
        if (@TypeOf(v) != MicroBenchFn) continue;

        var name = d.name;

        if (std.mem.startsWith(u8, d.name, "benchmark")) {
            name = d.name[9..];
        } else if (std.mem.startsWith(u8, d.name, "bench")) {
            name = d.name[5..];
        } else if (std.mem.startsWith(u8, d.name, "microBenchmark")) {
            name = d.name[14..];
        } else if (std.mem.startsWith(u8, d.name, "microBench")) {
            name = d.name[10..];
        }

        if (name.len == 0) name = d.name;

        const result = try microBench(v);
        const sample = result.sample;
        try w.print("{s}\t{D}/op\t{} alloc/op ({} bytes/op)\n", .{
            name,
            sample.time.ns / result.iter,
            sample.alloc.count / result.iter,
            sample.alloc.bytes / result.iter,
        });
    }
}

/// Generate a function of type `MicroBenchFn` with no setup and clean up.
///
/// Example:
///
/// ```zig
/// pub const benchMyFunc: zenith.MicroBenchFn = zenith.microBenchFn(myFunc, .{ arg1, arg2 });
/// // equivalent to:
/// pub fn benchMyFunc(m: *const zenith.M) void {
///     while (m.loop()) {
///         zenith.blackHole(
///             myFunc(zenith.blackBox(@TypeOf(arg1), &arg1), @TypeOf(arg2), &arg2)),
///         );
///     }
/// }
/// ```
pub fn microBenchFn(func: anytype, args: anytype) MicroBenchFn {
    const Args = @TypeOf(args);

    return struct {
        fn ubench(m: *const M) void {
            while (m.loop()) {
                var a = args;
                inline for (@typeInfo(Args).@"struct".fields) |f| {
                    const v = @field(a, f.name);
                    @field(a, f.name) = hint.blackBox(@TypeOf(v), &v);
                }

                hint.blackHole(@call(.always_inline, func, a));
            }
        }
    }.ubench;
}
