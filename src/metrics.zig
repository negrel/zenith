const std = @import("std");

/// High precision time metric for benchmarks.
pub const Time = struct {
    started: bool,
    timer: std.time.Timer,
    sample: Sample,

    pub const Sample = struct {
        const max: Sample = .{ .ns = std.math.maxInt(usize) };

        ns: usize,
    };

    pub fn init(self: *Time) !void {
        self.timer = try std.time.Timer.start();
        self.sample.ns = 0;
        self.started = false;
    }

    pub fn start(self: *Time) void {
        if (self.started) return;
        self.started = true;
        self.timer.reset();
    }

    pub fn stop(self: *Time) void {
        if (!self.started) return;
        self.started = false;
        self.sample.ns += self.timer.read();
    }
};

/// Allocation metrics for benchmarks.
pub const Alloc = struct {
    started: bool = false,
    sample: Sample = .{ .count = 0, .bytes = 0 },

    pub const Sample = struct {
        const max: Sample = .{
            .count = std.math.maxInt(usize),
            .bytes = std.math.maxInt(usize),
        };

        count: usize,
        bytes: usize,
    };

    pub fn init(self: *Alloc) !void {
        self.* = .{};
    }

    pub fn start(self: *Alloc) void {
        self.started = true;
    }

    pub fn stop(self: *Alloc) void {
        self.started = false;
    }

    pub fn reportAlloc(self: *Alloc, bytes: usize) void {
        if (!self.started or bytes == 0) return;
        self.sample.count += 1;
        self.sample.bytes += bytes;
    }
};

/// A collection of benchmark metrics.
pub const Bench = struct {
    time: Time,
    alloc: Alloc,

    pub const Sample = struct {
        pub const max: Sample = .{
            .time = Time.Sample.max,
            .alloc = Alloc.Sample.max,
        };

        time: Time.Sample,
        alloc: Alloc.Sample,
    };

    pub fn init(self: *Bench) !void {
        try self.time.init();
        try self.alloc.init();
    }

    pub fn start(self: *Bench) void {
        self.time.start();
        self.alloc.start();
    }

    pub fn stop(self: *Bench) void {
        self.time.stop();
        self.alloc.stop();
    }

    pub fn sample(self: *const Bench) Sample {
        return .{
            .time = self.time.sample,
            .alloc = self.alloc.sample,
        };
    }
};

test "Time" {
    var m: Time = undefined;
    try m.init();

    m.start();
    std.Thread.sleep(3 * std.time.ns_per_ms);
    m.stop();

    std.Thread.sleep(10 * std.time.ns_per_ms);

    m.start();
    std.Thread.sleep(3 * std.time.ns_per_ms);
    m.start(); // extra start (should be ignored)
    m.stop();
    m.stop(); // extra stop (should be ignored)

    try std.testing.expect(m.sample.ns > 6 * std.time.ns_per_ms);
    try std.testing.expect(m.sample.ns < 10 * std.time.ns_per_ms);
}

test "Alloc" {
    var m: Alloc = undefined;
    try m.init();

    m.reportAlloc(100);

    m.start();
    m.stop();

    m.start();
    m.reportAlloc(256);
    m.start();
    m.stop();
    m.stop();

    m.start();
    m.reportAlloc(1024);
    m.reportAlloc(0); // ignored
    m.stop();

    try std.testing.expectEqual(1024 + 256, m.sample.bytes);
    try std.testing.expectEqual(2, m.sample.count);
}
