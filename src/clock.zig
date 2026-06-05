const std = @import("std");

const optim = @import("optim.zig");

/// System clock precision (in nanoseconds) is the smallest nonzero time
/// interval measurable.
pub fn measurePrecision(io: std.Io) std.Io.Duration {
    var min_sample: std.Io.Duration = .fromNanoseconds(std.math.maxInt(i96));
    var seen_count: usize = 0;
    var delay_iter: usize = 0;

    var start = std.Io.Timestamp.now(io, .awake);

    while (true) {
        var prec_sample: std.Io.Duration = undefined;
        for (0..100) |_| {
            start = .now(io, .awake);
            if (delay_iter == 0) {
                prec_sample = start.untilNow(io, .awake);
            } else {
                for (0..delay_iter) |i| {
                    optim.blackHole(i);
                }
                prec_sample = start.untilNow(io, .awake);
            }

            if (prec_sample.nanoseconds == 0) continue;

            switch (std.math.order(
                prec_sample.nanoseconds,
                min_sample.nanoseconds,
            )) {
                .lt => {
                    min_sample = prec_sample;
                    seen_count = 0;
                },
                .eq => {
                    seen_count += 1;
                    if (seen_count >= 100) return min_sample;
                },
                .gt => {
                    if (delay_iter > 100) return min_sample;
                },
            }
        }

        delay_iter += 1;
    }
}

/// Measure system clock precision (in nanoseconds) and cache it globally.
/// This function calls measurePrecision() behind the scene and panic on error.
pub fn precision(io: std.Io) std.Io.Duration {
    const static = struct {
        var prec: ?std.Io.Duration = null;
    };

    if (static.prec) |p| {
        return p;
    }

    static.prec = measurePrecision(io);
    return precision(io);
}

test "measurePrecision" {
    try std.testing.expect(measurePrecision(std.testing.io).nanoseconds > 0);
}
