//! Benchmark metrics.

const std = @import("std");

const Metrics = @This();

time: Time,
alloc: Alloc,

/// A group of metrics sample.
pub const SampleGroup = struct {
    pub const max: SampleGroup = .{
        .time = Time.Sample.max,
        .alloc = Alloc.Sample.max,
    };

    time: Time.Sample,
    alloc: Alloc.Sample,
};

pub fn init(self: *Metrics, io: std.Io) !void {
    try self.time.init(io);
    try self.alloc.init();
}

/// Start / resume metrics recording.
pub fn start(self: *Metrics, io: std.Io) void {
    self.time.start(io);
    self.alloc.start();
}

/// Stop metrics recording.
pub fn stop(self: *Metrics, io: std.Io) void {
    self.time.stop(io);
    self.alloc.stop();
}

pub fn sample(self: *const Metrics) SampleGroup {
    return .{
        .time = self.time.sample,
        .alloc = self.alloc.sample,
    };
}

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

test Time {
    var vtable = std.Io.failing.vtable.*;
    vtable.now = struct {
        const timestamps: [5]std.Io.Timestamp = .{
            .fromNanoseconds(0), // init
            .fromNanoseconds(1), // start
            .fromNanoseconds(4), // stop
            .fromNanoseconds(14), // start
            .fromNanoseconds(17), // stop
        };

        var count: usize = 0;

        fn now(
            udata: ?*anyopaque,
            clock: std.Io.Clock,
        ) std.Io.Timestamp {
            defer count += 1;
            std.debug.assert(udata == null);
            std.debug.assert(clock == .awake);
            return timestamps[count];
        }
    }.now;
    const io: std.Io = .{ .userdata = null, .vtable = &vtable };

    var m: Time = undefined;
    try m.init(io);

    m.start(io);
    // try io.sleep(.fromMilliseconds(3), .awake);
    m.stop(io);

    // try io.sleep(.fromMilliseconds(10), .awake);

    m.start(io);
    // try io.sleep(.fromMilliseconds(3), .awake);
    m.start(io); // extra start (ignored)
    m.stop(io);
    m.stop(io); // extra stop (ignored)

    try std.testing.expect(m.sample.dur.toNanoseconds() == 6);
}

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

test Alloc {
    var m: Alloc = undefined;
    try m.init();

    m.reportAlloc(100);

    m.start();
    m.stop();

    m.reportAlloc(200);

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
