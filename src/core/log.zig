//! Debug file logging for ZigZag applications.
//! Since stdout is owned by the renderer, this provides file-based logging.

const std = @import("std");
const runtime_time = @import("../time_compat.zig");

/// Logger that writes timestamped messages to a file
pub const Logger = struct {
    file: std.Io.File,
    mutex: std.Io.Mutex,

    /// Initialize a logger that writes to the given file path
    pub fn init(path: []const u8) !Logger {
        const file = try std.Io.Dir.cwd().createFile(std.Options.debug_io, path, .{ .truncate = false });
        return .{
            .file = file,
            .mutex = .init,
        };
    }

    /// Close the log file
    pub fn deinit(self: *Logger) void {
        self.file.close(std.Options.debug_io);
    }

    /// Write a log message with timestamp prefix
    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.mutex.lockUncancelable(std.Options.debug_io);
        defer self.mutex.unlock(std.Options.debug_io);

        var write_buffer: [1024]u8 = undefined;
        var writer = self.file.writer(std.Options.debug_io, &write_buffer);
        defer {
            writer.flush() catch {};
        }
        writer.seekTo(self.file.length(std.Options.debug_io) catch return) catch return;

        // Write timestamp
        const now = runtime_time.wallNowSeconds();
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const day_seconds = epoch_seconds.getDaySeconds();

        writer.interface.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch return;

        // Write message
        writer.interface.print(fmt, args) catch return;
        writer.interface.writeByte('\n') catch return;
    }
};
