//! HostInfo returns info of current host.

const std = @import("std");
const builtin = @import("builtin");

const clock = @import("./clock.zig");

const HostInfo = @This();

target: std.Target,
clock_prec_ns: u64,

/// Initialize host info for current target.
pub fn init() HostInfo {
    return .{
        .target = builtin.target,
        .clock_prec_ns = clock.precision(),
    };
}

/// Print host info on the given writer.
pub fn print(self: *const HostInfo, w: *std.Io.Writer) !void {
    try w.print("cpu: {s}\narch: {s}\n", .{
        self.target.cpu.model.name,
        @tagName(self.target.cpu.arch),
    });

    try w.print("features:", .{});
    for (self.target.cpu.arch.allFeaturesList(), 0..) |feature, i_usize| {
        const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(i_usize));
        if (self.target.cpu.features.isEnabled(index)) {
            try w.print(" {s}", .{feature.name});
        }
    }
    try w.print("\nos: {s}\nabi: {s}\nsystem clock precision: {D}\n\n", .{
        @tagName(self.target.os.tag),
        @tagName(self.target.abi),
        self.clock_prec_ns,
    });
}
