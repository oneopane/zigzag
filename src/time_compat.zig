const std = @import("std");

pub const Deadline = struct {
    at_ns: u64,

    pub fn afterMilliseconds(timeout_ms: u64) Deadline {
        return afterNanoseconds(saturatingMul(timeout_ms, std.time.ns_per_ms));
    }

    pub fn afterNanoseconds(timeout_ns: u64) Deadline {
        return .{ .at_ns = saturatingAdd(monotonicNowNs(), timeout_ns) };
    }

    pub fn reached(self: Deadline) bool {
        return monotonicNowNs() >= self.at_ns;
    }
};

pub fn monotonicNowNs() u64 {
    const now = std.Io.Clock.awake.now(std.Options.debug_io);
    return std.math.cast(u64, now.toNanoseconds()) orelse 0;
}

pub fn wallNowSeconds() i64 {
    return std.Io.Clock.real.now(std.Options.debug_io).toSeconds();
}

pub fn sleepNs(nanoseconds: u64) void {
    if (nanoseconds == 0) return;

    const duration = std.Io.Clock.Duration{
        .clock = .awake,
        .raw = std.Io.Duration.fromNanoseconds(@intCast(nanoseconds)),
    };
    duration.sleep(std.Options.debug_io) catch {};
}

fn saturatingAdd(lhs: u64, rhs: u64) u64 {
    return std.math.add(u64, lhs, rhs) catch std.math.maxInt(u64);
}

fn saturatingMul(lhs: u64, rhs: u64) u64 {
    return std.math.mul(u64, lhs, rhs) catch std.math.maxInt(u64);
}
