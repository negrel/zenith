const std = @import("std");

const optim = @import("optim.zig");

/// System clock precision (in nanoseconds) is the smallest nonzero time
/// interval measurable.
pub fn measurePrecision() std.time.Timer.Error!u64 {
    var min_sample: u64 = std.math.maxInt(u64);
    var seen_count: usize = 0;
    var delay_iter: usize = 0;

    var timer: std.time.Timer = try std.time.Timer.start();

    while (true) {
        var prec_sample: usize = undefined;
        for (0..100) |_| {
            if (delay_iter == 0) {
                timer.reset();
                prec_sample = timer.read();
            } else {
                timer.reset();
                for (0..delay_iter) |i| {
                    optim.blackHole(i);
                }
                prec_sample = timer.read();
            }

            if (prec_sample == 0) continue;

            switch (std.math.order(prec_sample, min_sample)) {
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
pub fn precision() u64 {
    const static = struct {
        var prec: ?u64 = null;
    };

    if (static.prec) |p| {
        return p;
    }

    static.prec = measurePrecision() catch @panic("no system clock");
    return precision();
}

test "measurePrecision" {
    const prec = try measurePrecision();
    try std.testing.expect(prec > 0);
}
