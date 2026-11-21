const builtin = @import("builtin");
const std = @import("std");
const options = @import("options");

const Allocator = @import("./Allocator.zig");
const metrics = @import("./metrics.zig");
const clock = @import("./clock.zig");
const HostInfo = @import("./HostInfo.zig");
const optim = @import("./optim.zig");

const io = std.Options.debug_io;

/// Private zenith data part of benchmark context.
const Private = struct {
    iter: usize,
    metrics: metrics.Bench,
    clock_prec: std.Io.Duration,
    allocator: Allocator,

    fn init(self: *Private) !void {
        self.iter = 0;
        try self.metrics.init(io);
        self.clock_prec = clock.precision(io);
    }

    fn loop(self: *Private) bool {
        const m = &self.metrics;
        m.stop(io);
        if (self.iter > 0 and
            m.time.sample.dur.nanoseconds > 100 * self.clock_prec.nanoseconds)
            return false;
        self.iter += 1;
        m.start(io);
        return true;
    }
};

/// Context passed to micro benchmark functions.
pub const M = struct {
    /// Private field used by zenith.
    private: *const Private,

    fn prv(self: *const M) *Private {
        return @constCast(self.private);
    }

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
        return self.prv().loop();
    }

    /// Wrap allocator and returns a new allocator that track allocations.
    pub fn wrapAllocator(
        self: *const M,
        alloc: std.mem.Allocator,
    ) std.mem.Allocator {
        self.prv().allocator = .init(alloc, &self.prv().metrics);
    }
};

/// A micro benchmark function that accepts a benchmarking context M.
pub const MicroBenchFn = fn (*const M) void;

/// Micro benchmark output.
pub const MicroBenchmark = struct {
    samples: usize,
    iterations: usize,
    metrics: metrics.Bench.Sample,
    clock_prec: std.Io.Duration,
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
    if (builtin.mode == .debug and !options.allow_debug)
        @compileError("you should not run benchmark on non optimized build (set allow_debug options to true)");

    var result: MicroBenchmark = .{
        .samples = 0,
        .iterations = std.math.maxInt(usize),
        .metrics = metrics.Bench.Sample.max,
        .clock_prec = clock.precision(io),
    };

    var total_duration: std.Io.Duration = .zero;

    while (result.samples < options.sample_count_min or
        (@divTrunc(total_duration.nanoseconds, std.time.ns_per_ms) < options.duration_ms_max and
            result.samples < (options.sample_count_max orelse std.math.maxInt(u32))))
    {
        var private: Private = undefined;
        try private.init();

        var m = M{ .private = &private };

        ubench_fn(&m);

        if (private.iter == 0) @panic("benchmark function never called loop()");
        const sample = private.metrics.sample();

        if (sample.time.dur.nanoseconds < private.clock_prec.nanoseconds)
            @panic("sample time is lower than system clock precision, " ++
                " check your benchmark code");

        if (sample.time.dur.nanoseconds < result.metrics.time.dur.nanoseconds) {
            result = .{
                .samples = result.samples,
                .metrics = sample,
                .iterations = private.iter,
                .clock_prec = private.clock_prec,
            };
        }

        result.samples += 1;
        total_duration.nanoseconds += result.metrics.time.dur.nanoseconds;
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
///         while (m.loop()) {
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
    var stderr = try io.lockStderr(buf[0..], null);
    defer io.unlockStderr();
    var w = &stderr.file_writer.interface;

    if (!static.host_info_printed) {
        static.host_info_printed = true;

        if (options.run) {
            try HostInfo.init(io).print(w);
        } else {
            try w.print("zenith benchmarks skipped.\n", .{});
        }
    }
    if (!options.run) return;

    inline for (ti.decl_names) |d_name| {
        const v = @field(T, d_name);
        if (@TypeOf(v) != MicroBenchFn) continue;

        var name = d_name;

        if (std.mem.startsWith(u8, name, "benchmark")) {
            name = name[9..];
        } else if (std.mem.startsWith(u8, name, "bench")) {
            name = name[5..];
        } else if (std.mem.startsWith(u8, name, "microBenchmark")) {
            name = name[14..];
        } else if (std.mem.startsWith(u8, name, "microBench")) {
            name = name[10..];
        }

        if (name.len == 0) name = d_name;

        const result = try microBench(v);
        const sample = result.metrics;
        try w.print("{s}/{s}\t{f}/op\t{} alloc/op ({} bytes/op)\t{} iterations\t {} samples\n", .{
            @typeName(T),
            name,
            std.Io.Duration.fromNanoseconds(
                @divTrunc(sample.time.dur.nanoseconds, result.iterations),
            ),
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
                optim.voidCall(.never_inline, func, args);
            }
        }
    }.ubench;
}

test "microBenchNamespaceFib" {
    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(
        std.testing.io,
        "./examples/fib",
        std.testing.allocator,
    );
    defer std.testing.allocator.free(cwd);

    var proc = try std.process.spawn(std.testing.io, .{
        .argv = &.{
            "zig",
            "build",
            "test",
            "-Doptimize=ReleaseFast",
            "-Dbench",
        },
        .cwd = .{ .path = cwd },
        .stdout = .inherit,
        .stderr = .pipe,
    });

    var buf: [4096]u8 = undefined;
    var stderr_r = proc.stderr.?.reader(std.testing.io, &buf);
    var r = &stderr_r.interface;

    const prefixes: []const []const u8 = &.{
        "\x1B[0m" ++ "cpu:",
        "arch:",
        "features:",
        "os:",
        "abi:",
        "system clock precision:",
    };
    // Skip first two lines.
    _ = try r.takeDelimiter('\n');
    _ = try r.takeDelimiter('\n');

    var i: usize = 0;
    while (try r.takeDelimiter('\n')) |line| {
        if (i < prefixes.len) {
            try std.testing.expect(std.mem.startsWith(u8, line, prefixes[i]));
        } else if (i == prefixes.len) {
            try std.testing.expectEqualStrings("", line);
        } else if (line.len != 0) {
            if (!std.mem.startsWith(u8, line, "root.test.zenith")) break;

            var cols = std.mem.splitScalar(u8, line, '\t');
            var col = cols.next().?;
            col = cols.next().?;
            try std.testing.expect(std.mem.endsWith(u8, col, "s/op"));
            col = cols.next().?;
            try std.testing.expect(std.mem.endsWith(u8, col, "bytes/op)"));
            col = cols.next().?;
            try std.testing.expect(std.mem.endsWith(u8, col, "iterations"));
        }

        i += 1;
    }
    // prefixes + 1 one empty line + 2 benchmark
    try std.testing.expectEqual(prefixes.len + 3, i);

    const term = try proc.wait(std.testing.io);
    try std.testing.expectEqual(0, term.exited);
}
