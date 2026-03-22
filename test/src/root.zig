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

test "zenith.microBench" {
    try zenith.microBenchNamespace(struct {
        pub const benchFibIterative = zenith.microBenchFn(fibIterative, .{30});
        pub const benchFibRecursive = zenith.microBenchFn(fibRecursive, .{30});
    });
}
