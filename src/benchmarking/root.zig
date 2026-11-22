const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}

pub const clock = @import("./clock.zig").awake;

const optim = @import("./optim.zig");
pub const blackHole = optim.blackHole;
pub const blackBox = optim.blackBox;
