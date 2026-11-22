const std = @import("std");
const testing = std.testing;

const optim = @import("optim.zig");

test {
    testing.refAllDecls(@This());
}

/// A nonsettable system-wide clock that represents time since some unspecified
/// point in the past.
///
/// Monotonic: Guarantees that the time returned by consecutive calls will not
/// go backwards, but successive calls may return identical (not-increased)
/// time values.
///
/// Not affected by discontinuous jumps in the system time (e.g., if the system
/// administrator manually changes the clock), but may be affected by frequency
/// adjustments.
///
/// This clock expresses intent to exclude time that the system is suspended.
/// However, implementations may be unable to satisify this, and may include
/// that time.
///    On Linux, corresponds CLOCK_MONOTONIC.
///    On macOS, corresponds to CLOCK_UPTIME_RAW.
pub const awake = struct {
    const io = std.Io.Threaded.global_single_threaded.io();

    /// Read monotonic clock and return value that represents time since some
    /// unspecified point in the past.
    ///
    /// This function performs 0 syscall and doesn't block.
    pub fn now() std.Io.Timestamp {
        return io.vtable.now(io.userdata, .awake);
    }

    /// Reveals the granularity of clock. May be zero, indicating unsupported
    /// clock.
    ///
    /// This function performs a syscall and may block.
    pub fn resolution() std.Io.Duration {
        return std.Io.Clock.awake.resolution(io) catch .fromNanoseconds(0);
    }

    /// Measure clock precision and returns it.
    ///
    /// Returned precision is cached in-memory for later retrieval.
    pub fn precision() std.Io.Duration {
        const cached = struct {
            var precision: ?std.Io.Duration = null;
        };
        if (cached.precision) |p| return p;
        cached.precision = measurePrecision(now);
        return cached.precision.?;
    }

    test precision {
        try testing.expect(precision().nanoseconds > 0);
    }
};

/// A static clock that returns predefined timestamps.
///
/// This clock is used for testing.
pub fn static(timestamps: []const std.Io.Timestamp) type {
    return struct {
        pub var static_precision: std.Io.Duration = undefined;
        var count: usize = 0;

        pub fn now() std.Io.Timestamp {
            const ts = timestamps[count];
            count += 1;
            return ts;
        }

        pub fn precision() std.Io.Duration {
            return static_precision;
        }
    };
}

const measure_per_iter = 100;

/// Measure system clock precision (in nanoseconds).
///
/// System clock precision is the smallest nonzero time interval measurable.
fn measurePrecision(clockNow: fn () std.Io.Timestamp) std.Io.Duration {
    var min_prec: std.Io.Duration = .fromNanoseconds(std.math.maxInt(i96));
    var seen_count: usize = 0;
    var delay_iter: usize = 0;

    var start: std.Io.Timestamp = undefined;

    while (true) {
        var prec: std.Io.Duration = undefined;
        for (0..measure_per_iter) |_| {
            start = clockNow();
            for (0..delay_iter) |i| {
                optim.blackHole(i);
            }
            prec = start.durationTo(clockNow());

            if (prec.nanoseconds == 0) continue;

            switch (std.math.order(
                prec.nanoseconds,
                min_prec.nanoseconds,
            )) {
                .lt => {
                    min_prec = prec;
                    seen_count = 1;
                },
                .eq => {
                    seen_count += 1;
                    if (seen_count >= measure_per_iter) return min_prec;
                },
                .gt => continue,
            }
        }

        delay_iter +|= 1;
    }
}

test measurePrecision {
    const prec = measurePrecision(awake.now);

    try testing.expect(prec.nanoseconds > 0);
    try testing.expect(
        prec.nanoseconds >= awake.resolution().nanoseconds,
    );
}

test "measurePrecision with monotonic clock (1ns)" {
    const iters = 2;
    const now_per_measure = 2;
    const len = iters * measure_per_iter * now_per_measure;

    const timestamps: [len]std.Io.Timestamp = comptime ts: {
        var ts: [len]std.Io.Timestamp = undefined;
        for (0..len) |i|
            ts[i] = .fromNanoseconds(i);
        break :ts ts;
    };

    try testing.expectEqual(
        1,
        measurePrecision(static(&timestamps).now).nanoseconds,
    );
}

test "measurePrecision with monotonic clock (2ns)" {
    const iters = 2;
    const now_per_measure = 2;
    const len = iters * measure_per_iter * now_per_measure;

    const timestamps: [len]std.Io.Timestamp = comptime ts: {
        var ts: [len]std.Io.Timestamp = undefined;
        for (0..len) |i|
            ts[i] = .fromNanoseconds(2 * i);
        break :ts ts;
    };
    try testing.expectEqual(
        2,
        measurePrecision(static(&timestamps).now).nanoseconds,
    );
}

test "measurePrecision with clock more precise on 2nd iter" {
    const iters = 2;
    const now_per_measure = 2;
    const len = iters * measure_per_iter * now_per_measure;
    const ts_per_iter = len / iters;

    const timestamps: [len]std.Io.Timestamp = comptime ts: {
        var ts: [len]std.Io.Timestamp = undefined;
        for (0..ts_per_iter) |i|
            ts[i] = .fromNanoseconds(0);

        for (ts_per_iter..2 * ts_per_iter) |i|
            ts[i] = .fromNanoseconds(1 + i);
        break :ts ts;
    };

    try testing.expectEqual(
        1,
        measurePrecision(static(&timestamps).now).nanoseconds,
    );
}

test "measurePrecision with clock more precise on 1.5 - 2.5 iter" {
    const iters = 2;
    const now_per_measure = 2;
    const len = iters * measure_per_iter * now_per_measure;
    const ts_per_iter = len / iters;

    const timestamps: [len]std.Io.Timestamp = comptime ts: {
        var ts: [len]std.Io.Timestamp = undefined;
        for (0..ts_per_iter / 2) |i|
            ts[i] = .fromNanoseconds(0);
        for (ts_per_iter / 2..ts_per_iter + ts_per_iter / 2) |i|
            ts[i] = .fromNanoseconds(1 + i);

        for (ts_per_iter * 3 / 2..2 * ts_per_iter) |i|
            ts[i] = .fromNanoseconds(0);
        break :ts ts;
    };

    try testing.expectEqual(
        1,
        measurePrecision(static(&timestamps).now).nanoseconds,
    );
}
