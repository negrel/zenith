//! Compiler hint functions.

const std = @import("std");

/// A function that is opaque to the optimizer, used to prevent the compiler
/// from optimizing away computations in a benchmark.
///
/// Example:
///
/// ```zig
/// // Work won't be optimized even though it use a constant argument.
/// std.mem.doNotOptimizeAway(work(blackBox(usize, &128)));
/// ```
pub fn blackBox(T: type, v: *const volatile T) T {
    return v.*;
}

/// Force an evaluation of the expression; this tries to prevent the compiler
/// from optimizing the computation away even if the result eventually gets
/// discarded.
pub fn blackHole(val: anytype) void {
    std.mem.doNotOptimizeAway(val);
}
