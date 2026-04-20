const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");

const Allocator = @import("./Allocator.zig");
const metrics = @import("./metrics.zig");
const clock = @import("./clock.zig");
const HostInfo = @import("./HostInfo.zig");
const optim = @import("./optim.zig");

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
    samples: usize,
    iterations: usize,
    metrics: metrics.Bench.Sample,
    clock_prec_ns: u64,
};

/// Measure the performance of `ubench_fn` function. Micro benchmark are
/// tailored to measure performance of single threaded code (no contention)
/// with an execution time in the range of few nanoseconds to hundred
/// milliseconds.
///
/// Low-level function; prefer using microBenchNamespace instead.
///
/// Panics if `zenith.options.run` is `false` or if the build is in debug mode.
///
/// Accounts for system clock precision and reduces interference from OS
/// scheduling, context switches, CPU frequency scaling, and similar effects.
///
/// Repeatedly runs `ubench_fn` and returns the shortest observed execution
/// time (the sample with the least added delay).
pub fn microBench(ubench_fn: MicroBenchFn) !MicroBenchmark {
    if (!options.run)
        @panic("zenith.options.run is false, benchmarks disabled. " ++
            "Set 'run' build options to true to enable benchmarks.");
    if (builtin.mode == .Debug and !options.allow_debug)
        @compileError("you should not run benchmark on non optimized build (set allow_debug options to true)");

    var result: MicroBenchmark = .{
        .samples = 0,
        .iterations = std.math.maxInt(usize),
        .metrics = metrics.Bench.Sample.max,
        .clock_prec_ns = clock.precision(),
    };

    var total_duration_ns: usize = 0;

    while (result.samples < options.sample_count_min or
        ((total_duration_ns / std.time.ns_per_ms) < options.duration_ms_max and
            result.samples < (options.sample_count_max orelse std.math.maxInt(u32))))
    {
        var private: Private = undefined;
        try private.init();

        var testing_alloc = @TypeOf(std.testing.allocator_instance).init;
        var alloc = Allocator.init(
            testing_alloc.allocator(),
            &private.metrics.alloc,
        );

        var m = M{
            .private = &private,
            .allocator = alloc.allocator(),
        };

        ubench_fn(&m);

        if (private.iter == 0) @panic("benchmark function never called loop()");
        const sample = private.metrics.sample();

        if (sample.time.ns < private.clock_prec_ns)
            @panic("sample time is lower than system clock precision, " ++
                " check your benchmark code");

        if (sample.time.ns < result.metrics.time.ns) {
            result = .{
                .samples = result.samples,
                .metrics = sample,
                .iterations = private.iter,
                .clock_prec_ns = private.clock_prec_ns,
            };
        }

        try std.testing.expectEqual(.ok, testing_alloc.deinit());

        result.samples += 1;
        total_duration_ns += result.metrics.time.ns;
    }

    return result;
}

/// Micro benchmark all public function of type `MicroBenchFn` contained in
/// struct / namespace `T` and prints result to stderr. This function is no-op
/// if `zenith.options.run` is set to `false`.
///
/// Examples:
///
/// ```zig
/// try zenith.microBenchNamespace(@This());
///
/// try zenith.microBenchNamespace(struct {
///     fn myBench(m: *const zenith.M) void {
///         // Setup.
///         // ...
///
///         for (m.loop()) {
///             // Use black hole to prevent compiler from optimizing output of
///             // function.
///             // Use black box to prevent compiler from optimizing input of
///             // function.
///             zenith.blackHole(myFunc(zenith.blackBox(usize, &30)))
///         }
///
///         // Cleanup.
///         // ...
///     }
///
///     // If you have no setup/cleanup:
///     const myBench2 = zenith.microBenchFn(myFunc, .{@as(usize, 30)})
/// });
/// ```
pub fn microBenchNamespace(T: type) !void {
    const static = struct {
        var host_info_printed = false;
    };

    const ti = @typeInfo(T).@"struct";

    var buf: [4096]u8 = undefined;
    var w = std.Progress.lockStderrWriter(buf[0..]);
    defer std.Progress.unlockStderrWriter();

    if (!options.run) {
        try w.print("zenith benchmarks skipped.\n", .{});
        return;
    }

    if (!static.host_info_printed) {
        try HostInfo.init().print(w);
        static.host_info_printed = true;
    }

    inline for (ti.decls) |d| {
        const v = @field(T, d.name);
        if (@TypeOf(v) != MicroBenchFn) continue;

        var name = d.name;

        if (std.mem.startsWith(u8, name, "benchmark")) {
            name = name[9..];
        } else if (std.mem.startsWith(u8, name, "bench")) {
            name = name[5..];
        } else if (std.mem.startsWith(u8, name, "microBenchmark")) {
            name = name[14..];
        } else if (std.mem.startsWith(u8, name, "microBench")) {
            name = name[10..];
        }

        if (name.len == 0) name = d.name;

        const result = try microBench(v);
        const sample = result.metrics;
        try w.print("{s}/{s}\t{D}/op\t{} alloc/op ({} bytes/op)\t{} iterations\t {} samples\n", .{
            @typeName(T),
            name,
            sample.time.ns / result.iterations,
            sample.alloc.count / result.iterations,
            sample.alloc.bytes / result.iterations,
            result.iterations,
            result.samples,
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
    return struct {
        fn ubench(m: *const M) void {
            while (m.loop()) {
                optim.voidCall(.always_inline, func, args);
            }
        }
    }.ubench;
}

test "microBenchNamespaceFib" {
    var proc = std.process.Child.init(&.{
        "zig",
        "build",
        "test",
        "-Doptimize=ReleaseFast",
        "-Dbench",
    }, std.testing.allocator);
    proc.cwd = try std.fs.cwd().realpathAlloc(
        std.testing.allocator,
        "./examples/fib",
    );
    defer std.testing.allocator.free(proc.cwd.?);

    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    try proc.spawn();

    var buf: [4096]u8 = undefined;

    const read = try proc.stderr.?.readAll(buf[0..]);

    const prefixes: []const []const u8 = &.{
        "cpu:",
        "arch:",
        "features:",
        "os:",
        "abi:",
        "system clock precision:",
    };
    var lines = std.mem.splitScalar(u8, buf[0..read], '\n');
    // Skip first two lines.
    _ = lines.next().?;
    _ = lines.next().?;

    var i: usize = 0;
    while (lines.next()) |l| {
        defer i += 1;

        var line = l;

        // Skip ansi escape sequence on first line.
        if (i == 0) line = l[8..];

        if (i < prefixes.len) {
            try std.testing.expect(std.mem.startsWith(u8, line, prefixes[i]));
        } else if (i == prefixes.len) {
            try std.testing.expectEqualStrings("", line);
        } else if (line.len != 0) {
            var cols = std.mem.splitScalar(u8, line, '\t');
            var col = cols.next().?;
            try std.testing.expect(std.mem.startsWith(u8, col, "Fib"));
            col = cols.next().?;
            try std.testing.expect(std.mem.endsWith(u8, col, "s/op"));
            col = cols.next().?;
            try std.testing.expect(std.mem.endsWith(u8, col, "bytes/op)"));
        }
    }
    try std.testing.expect(i > prefixes.len + 2);

    const term = try proc.wait();
    try std.testing.expectEqual(0, term.Exited);
}
