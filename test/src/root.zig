const std = @import("std");

const zenith = @import("zenith");

/// Recursive version of fibonacci.
fn fibRecursive(n: usize) usize {
    if (n < 2) return n;
    return fibRecursive(n - 2) + fibRecursive(n - 1);
}

/// Iterative version of fibonacci.
fn fibIterative(n: usize) usize {
    if (n < 2) return n;

    var prev: usize = 0;
    var last: usize = 1;

    for (2..n + 1) |_| {
        const next = last + prev;
        prev = last;
        last = next;
    }

    return last;
}

fn microBenchFibRecursive(m: *const zenith.M) void {
    while (m.loop()) {
        zenith.blackHole(fibRecursive(zenith.blackBox(usize, &30)));
    }
}

fn microBenchFibIterative(m: *const zenith.M) void {
    while (m.loop()) {
        zenith.blackHole(fibIterative(zenith.blackBox(usize, &30)));
    }
}

test "zenith.microBench" {
    const rec = try zenith.microBench(microBenchFibRecursive);
    std.debug.print("{D} +- {D}\n", .{ rec.sample.time.ns / rec.iter, rec.sample.time.ns / rec.iter / 100 });
    std.debug.print("---\n", .{});
    const iter = try zenith.microBench(microBenchFibIterative);
    std.debug.print("{D} +- {D}\n", .{ iter.sample.time.ns / iter.iter, iter.sample.time.ns / iter.iter / 100 });
}
