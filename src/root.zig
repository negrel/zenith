//! Reach Zenith of Zig performance.

const builtin = @import("builtin");
const std = @import("std");

pub const options = @import("options");

test {
    _ = @import("./clock.zig");
    _ = @import("./metrics.zig");
    _ = @import("./Allocator.zig");
    _ = @import("./bench.zig");
}

const optim = @import("./optim.zig");
pub const blackBox = optim.blackBox;
pub const blackHole = optim.blackHole;
pub const call = optim.call;

const bench = @import("./bench.zig");
pub const microBench = bench.microBench;
pub const microBenchNamespace = bench.microBenchNamespace;
pub const microBenchFn = bench.microBenchFn;
pub const MicroBenchmark = bench.MicroBenchmark;
pub const MicroBenchFn = bench.MicroBenchFn;
pub const M = bench.M;
