const std = @import("std");

/// High precision time metric for benchmarks.
pub const Time = struct {
    started: bool,
    previous: std.Io.Timestamp,
    sample: Sample,

    pub const Sample = struct {
        const max: Sample = .{ .dur = .max };

        dur: std.Io.Duration,
    };

    pub fn init(
        self: *Time,
        io: std.Io,
    ) !void {
        self.previous = std.Io.Timestamp.now(io, .awake);
        self.sample.dur = .fromNanoseconds(0);
        self.started = false;
    }

    pub fn start(self: *Time, io: std.Io) void {
        if (self.started) return;
        self.started = true;
        self.previous = std.Io.Timestamp.now(io, .awake);
    }

    pub fn stop(self: *Time, io: std.Io) void {
        if (!self.started) return;
        self.started = false;
        self.sample.dur.nanoseconds += self.previous.untilNow(
            io,
            .awake,
        ).toNanoseconds();
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

    pub fn init(self: *Bench, io: std.Io) !void {
        try self.time.init(io);
        try self.alloc.init();
    }

    pub fn start(self: *Bench, io: std.Io) void {
        self.time.start(io);
        self.alloc.start();
    }

    pub fn stop(self: *Bench, io: std.Io) void {
        self.time.stop(io);
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
    const io = std.testing.io;

    var m: Time = undefined;
    try m.init(io);

    m.start(io);
    try io.sleep(.fromMilliseconds(3), .awake);
    m.stop(io);

    try io.sleep(.fromMilliseconds(10), .awake);

    m.start(io);
    try io.sleep(.fromMilliseconds(3), .awake);
    m.start(io); // extra start (should be ignored)
    m.stop(io);
    m.stop(io); // extra stop (should be ignored)

    try std.testing.expect(m.sample.dur.toMilliseconds() >= 6);
    try std.testing.expect(m.sample.dur.toMilliseconds() < 10);
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
