const std = @import("std");
const Io = std.Io;
const mem = std.mem;

const benchmarking = @import("benchmarking");

const Cli = struct {
    args: [][]const u8,
    io: Io,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
};

/// Exit code used on I/O errors.
const EIO: u8 = @backingInt(std.c.E.IO);

pub fn main(init: std.process.Init.Minimal) !void {
    var args_iter = init.args.iterate();

    // zenith executes itself as 'true' to calibrate itself.
    if (mem.eql(u8, args_iter.next() orelse "true", "true")) return;

    var safe_allocator: std.heap.SafeAllocator = .init(
        std.heap.page_allocator,
        .{},
    );
    defer _ = safe_allocator.deinit();
    const gpa = safe_allocator.allocator();

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const args = init.args.toSlice(arena.allocator()) catch |e| fatal(e);

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    const io: std.Io = threaded.io();

    var stderr_buf: [4096]u8 = undefined;
    const stderr = std.Io.File.stderr();
    var stderr_w = stderr.writer(io, stderr_buf[0..]);

    var stdout_buf: [4096]u8 = undefined;
    const stdout = std.Io.File.stdout();
    var stdout_w = stdout.writer(io, stdout_buf[0..]);

    var cli: Cli = .{
        .args = arena.allocator().dupe(
            []const u8,
            args[1..],
        ) catch |e| fatal(e),
        .io = io,
        .stderr = &stderr_w.interface,
        .stdout = &stdout_w.interface,
    };
    var code = zenith(&cli);

    stderr_w.interface.flush() catch {
        if (code == 0) code = EIO;
    };
    stdout_w.interface.flush() catch {
        if (code == 0) code = EIO;
    };

    std.process.exit(code);
}

fn zenith(cli: *Cli) u8 {
    if (cli.args.len < 1)
        return cliError(cli.stderr, "missing COMMAND argument", .{});

    for (0..cli.args.len) |_| {
        const arg = cli.args[0];

        if (mem.eql(u8, arg, "-h") or
            mem.eql(u8, arg, "--help"))
            return help(cli.stdout);

        if (mem.eql(u8, arg, "--"))
            break;

        if (mem.startsWith(u8, arg, "-"))
            return cliError(cli.stderr, "unknown FLAG '{s}'", .{arg})
        else
            break;

        cli.args = cli.args[1..];
    }
    if (cli.args.len < 1)
        return cliError(cli.stderr, "missing COMMAND argument", .{});

    const clock_resolution = benchmarking.clock.resolution();
    const clock_precision = benchmarking.clock.precision();

    std.debug.print(
        \\clock resolution: {[clock_resolution]f}
        \\clock precision : {[clock_precision]f}
        \\
    , .{
        .clock_resolution = clock_resolution,
        .clock_precision = clock_precision,
    });

    var command = splitCommands(cli.args);
    while (command.next()) |cmd| {
        var proc = std.process.spawn(cli.io, .{
            .argv = cmd,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch |e| fatal(e);
        _ = proc.wait(cli.io) catch |e| fatal(e);
    }

    return 0;
}

fn help(w: *Io.Writer) u8 {
    w.print(
        \\zenith - A command-line benchmarking tool.
        \\
        \\Usage: zenith [FLAGS] COMMAND [...ARGS] [-- COMMAND [...ARGS]]
        \\       zenith --help
        \\       zenith ./my-cli-v1 --my-cli-v1-flag
        \\       zenith ./my-cli-v1 --my-cli-v1-flag -- ./mycli_v2 --my-cli-v2-flag
        \\
        \\  If you need to pass '--' as argument to a benchmarked command,
        \\  you can escape it using a backslash: '\\--'
        \\
        \\Flags:
        \\  -h, --help              Print this menu.
        \\
    ,
        .{},
    ) catch return EIO;

    return 0;
}

fn cliError(w: *Io.Writer, comptime fmt: []const u8, args: anytype) u8 {
    w.print("Error: ", .{}) catch return EIO;
    w.print(fmt, args) catch return EIO;
    w.print("\n\n", .{}) catch return EIO;
    w.print("Usage: zenith [FLAGS] COMMAND\n\n", .{}) catch return EIO;
    w.print("Run 'zenith -h' for more information.\n", .{}) catch return EIO;

    return 1;
}

fn fatal(err: anyerror) noreturn {
    @panic(@errorName(err));
}

/// An iterator over commands specified on the command line.
const CommandIterator = struct {
    args: [][]const u8,
    cursor: usize,

    pub fn next(self: *CommandIterator) ?[]const []const u8 {
        for (self.args[self.cursor..], 0..) |arg, i| {
            if (i > 0 and mem.eql(u8, arg, "--")) {
                defer self.cursor += i + 1;
                return self.args[self.cursor..][0..i];
            } else if (mem.eql(u8, arg, "\\--")) {
                self.args[self.cursor + i] = "--";
            }
        }

        if (self.cursor == self.args.len) return null;

        defer self.cursor = self.args.len;
        return self.args[self.cursor..];
    }
};

/// Returns an iterator over commands separated by a '--'.
fn splitCommands(args: [][]const u8) CommandIterator {
    return CommandIterator{
        .args = args,
        .cursor = 0,
    };
}

test splitCommands {
    inline for ([_]struct {
        []const []const u8, // input
        []const []const []const u8, // expected output
    }{
        .{ &.{""}, &.{&.{""}} },
        .{ &.{"--"}, &.{&.{"--"}} },
        .{ &.{ "--", "--" }, &.{&.{"--"}} },
        .{ &.{ "--", "--", "--" }, &.{ &.{"--"}, &.{"--"} } },
        .{ &.{ "--", "--", "--", "--" }, &.{ &.{"--"}, &.{"--"} } },
        .{ &.{"-- --help"}, &.{&.{"-- --help"}} },
        .{ &.{"true"}, &.{&.{"true"}} },
        .{ &.{ "true", "--help" }, &.{&.{ "true", "--help" }} },
        .{
            &.{ "true", "--help", "--", "--" },
            &.{ &.{ "true", "--help" }, &.{"--"} },
        },
        .{
            &.{ "true", "--help", "--", "--", "--" },
            &.{ &.{ "true", "--help" }, &.{"--"} },
        },
        .{
            &.{ "true", "--help", "--", "--", "--", "--" },
            &.{ &.{ "true", "--help" }, &.{"--"}, &.{"--"} },
        },
        .{
            &.{ "true", "--help", "--", "false", "--help" },
            &.{ &.{ "true", "--help" }, &.{ "false", "--help" } },
        },

        .{ &.{ "grep", "\\--", "--help" }, &.{&.{ "grep", "--", "--help" }} },
    }) |t| {
        var array: [32][]const u8 = undefined;
        @memcpy(array[0..t[0].len], t[0]);
        var iter = splitCommands(array[0..t[0].len]);

        for (t[1]) |cmd| {
            const actual = iter.next();

            try std.testing.expectEqualDeep(cmd, actual);
        }

        const last = iter.next();
        try std.testing.expectEqual(null, last);
    }
}
