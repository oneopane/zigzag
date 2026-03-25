const std = @import("std");
const builtin = @import("builtin");

pub fn getOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return std.process.Environ.getAlloc(currentEnviron(), allocator, name) catch null;
}

pub fn exists(name: []const u8) bool {
    return std.process.Environ.contains(currentEnviron(), std.heap.page_allocator, name) catch false;
}

fn currentEnviron() std.process.Environ {
    if (builtin.os.tag == .windows) {
        return .{ .block = .global };
    }

    var count: usize = 0;
    while (std.c.environ[count] != null) : (count += 1) {}
    return .{ .block = .{ .slice = std.c.environ[0..count :null] } };
}
