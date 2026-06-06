//! Utils functions to prevent the compiler from optimizing code.

const std = @import("std");
const builtin = @import("builtin");

/// A function that is opaque to the optimizer, used to prevent the compiler
/// from optimizing away computations in a benchmark.
///
/// Example:
///
/// ```zig
/// // Work won't be optimized even though it use a constant argument.
/// std.mem.doNotOptimizeAway(work(blackBox(usize, &128)));
/// ```
pub inline fn blackBox(T: type, v: *const volatile T) T {
    return v.*;
}

/// Force an evaluation of the expression; this tries to prevent the compiler
/// from optimizing the computation away even if the result eventually gets
/// discarded.
pub inline fn blackHole(val: anytype) void {
    std.mem.doNotOptimizeAway(val);
}

/// Call function `func` with arguments `args` and prevents the compiler from
/// optimizing the arguments (using `blackBox()`).
///
/// Signature is the same as the `@call` built-in.
pub inline fn call(
    modifier: std.builtin.CallModifier,
    func: anytype,
    args: anytype,
) @typeInfo(@TypeOf(func)).@"fn".return_type.? {
    const Args = @TypeOf(args);
    var a = args;
    inline for (@typeInfo(Args).@"struct".fields) |f| {
        const v = @field(a, f.name);
        @field(a, f.name) = blackBox(@TypeOf(v), &v);
    }

    return @call(modifier, func, a);
}

/// Same as `call` but returns void and prevents the compiler from optimizing
/// result returned by `func`.
pub inline fn voidCall(
    modifier: std.builtin.CallModifier,
    func: anytype,
    args: anytype,
) void {
    const result = call(modifier, func, args);
    blackHole(result);
}

fn fibRecur(n: usize) usize {
    if (n < 2) return n;
    return fibRecur(n - 2) + fibRecur(n - 1);
}

test "call" {
    if (builtin.mode == .Debug) return;
    const io = std.testing.io;

    var start = std.Io.Timestamp.now(io, .awake);

    // Compiler won't optimize this call.
    const result1 = call(.auto, fibRecur, .{40});
    const dur1 = start.untilNow(io, .awake);

    start = std.Io.Timestamp.now(io, .awake);

    // Compiler will execute this call at comptime.
    const result2 = fibRecur(40);
    const dur2 = start.untilNow(io, .awake);

    try std.testing.expect(result1 == result2);
    try std.testing.expect(dur1.nanoseconds > 10 * dur2.nanoseconds);
}

test "voidCall" {
    if (builtin.mode == .Debug) return;
    const io = std.testing.io;

    var start = std.Io.Timestamp.now(io, .awake);

    // Compiler won't optimize this call.
    voidCall(.auto, fibRecur, .{40});
    const dur1 = start.untilNow(io, .awake);

    start = std.Io.Timestamp.now(io, .awake);

    // Compiler will remove this call since result is discarded.
    _ = call(.auto, fibRecur, .{40});
    const dur2 = start.untilNow(io, .awake);

    try std.testing.expect(dur1.nanoseconds > 10 * dur2.nanoseconds);
}
