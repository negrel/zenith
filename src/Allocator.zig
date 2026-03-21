//! Benchmark allocator that collect metrics on allocation.

const std = @import("std");

const metrics = @import("./metrics.zig");

const Self = @This();
const Allocator = Self;

backing_allocator: std.mem.Allocator,
metric: *metrics.Alloc,

const vtable: std.mem.Allocator.VTable = .{
    .alloc = &alloc,
    .resize = &resize,
    .remap = &remap,
    .free = &free,
};

pub fn init(balloc: std.mem.Allocator, metric: *metrics.Alloc) Self {
    return .{ .backing_allocator = balloc, .metric = metric };
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return .{ .ptr = self, .vtable = &vtable };
}

fn alloc(
    ptr: *anyopaque,
    len: usize,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const alloc_ptr = self.backing_allocator.vtable.alloc(
        self.backing_allocator.ptr,
        len,
        alignment,
        ret_addr,
    );
    if (alloc_ptr) |_| {
        self.metric.reportAlloc(len);
    }
    return alloc_ptr;
}

fn resize(
    ptr: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const resize_ptr = self.backing_allocator.vtable.resize(
        self.backing_allocator.ptr,
        memory,
        alignment,
        new_len,
        ret_addr,
    );
    if (resize_ptr) {
        self.metric.reportAlloc(new_len);
    }
    return resize_ptr;
}

fn remap(
    ptr: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    new_len: usize,
    ret_addr: usize,
) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const remap_ptr = self.backing_allocator.vtable.remap(
        self.backing_allocator.ptr,
        memory,
        alignment,
        new_len,
        ret_addr,
    );
    if (remap_ptr) |_| {
        self.metric.reportAlloc(new_len);
    }
    return remap_ptr;
}

fn free(
    ptr: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    ret_addr: usize,
) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.backing_allocator.vtable.free(
        self.backing_allocator.ptr,
        memory,
        alignment,
        ret_addr,
    );
}

test "Allocator" {
    var metric: metrics.Alloc = undefined;
    try metric.init();
    metric.start();

    var a = Allocator.init(std.testing.allocator, &metric);
    var list = try std.ArrayListUnmanaged(u8).initCapacity(a.allocator(), 128);
    try list.ensureTotalCapacityPrecise(a.allocator(), 512);
    list.deinit(a.allocator());

    metric.stop();
    try std.testing.expectEqual(2, metric.sample.count);
    try std.testing.expectEqual(128 + 512, metric.sample.bytes);
}
