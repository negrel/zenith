const builtin = @import("builtin");
const std = @import("std");

pub const options = @import("options");

test {
    _ = @import("./clock.zig");
    _ = @import("./metrics.zig");
    _ = @import("./Allocator.zig");
}

const hint = @import("./hint.zig");
pub const blackBox = hint.blackBox;
pub const blackHole = hint.blackHole;

const bench = @import("./bench.zig");
pub const microBench = bench.microBench;
pub const MicroBenchmark = bench.MicroBenchmark;
pub const MicroBenchFn = bench.MicroBenchFn;
pub const M = bench.M;
