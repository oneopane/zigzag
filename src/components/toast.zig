//! Enhanced Toast/Snackbar notification system.
//! Supports positioning, stacking, icons, borders, and auto-dismiss with countdown.

const std = @import("std");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const border_mod = @import("../style/border.zig");
const measure = @import("../layout/measure.zig");

pub const Level = enum {
    info,
    success,
    warning,
    err,
};

pub const Position = enum {
    top_left,
    top_center,
    top_right,
    bottom_left,
    bottom_center,
    bottom_right,
};

pub const StackOrder = enum {
    newest_first,
    oldest_first,
};

pub const ToastMessage = struct {
    text: []const u8,
    level: Level,
    created_ns: u64,
    duration_ms: u64,
    dismissable: bool,
};

pub const Toast = struct {
    allocator: std.mem.Allocator,
    messages: std.array_list.Managed(ToastMessage),

    // Layout
    max_visible: usize,
    position: Position,
    stack_order: StackOrder,
    min_width: u16,
    max_width: u16,

    // Visual
    show_icons: bool,
    show_border: bool,
    show_countdown: bool,
    border_chars: border_mod.BorderChars,

    // Icons per level
    info_icon: []const u8,
    success_icon: []const u8,
    warning_icon: []const u8,
    err_icon: []const u8,

    // Styling per level
    info_style: style_mod.Style,
    success_style: style_mod.Style,
    warning_style: style_mod.Style,
    err_style: style_mod.Style,

    info_border_fg: Color,
    success_border_fg: Color,
    warning_border_fg: Color,
    err_border_fg: Color,

    pub fn init(allocator: std.mem.Allocator) Toast {
        return .{
            .allocator = allocator,
            .messages = std.array_list.Managed(ToastMessage).init(allocator),
            .max_visible = 5,
            .position = .top_right,
            .stack_order = .newest_first,
            .min_width = 20,
            .max_width = 50,
            .show_icons = true,
            .show_border = true,
            .show_countdown = false,
            .border_chars = border_mod.Border.rounded,
            .info_icon = "\u{2139}  ",
            .success_icon = "\u{2713} ",
            .warning_icon = "\u{26a0} ",
            .err_icon = "\u{2717} ",
            .info_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.cyan());
                s = s.inline_style(true);
                break :blk s;
            },
            .success_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.green());
                s = s.inline_style(true);
                break :blk s;
            },
            .warning_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.yellow());
                s = s.inline_style(true);
                break :blk s;
            },
            .err_style = blk: {
                var s = style_mod.Style{};
                s = s.bold(true);
                s = s.fg(Color.red());
                s = s.inline_style(true);
                break :blk s;
            },
            .info_border_fg = Color.cyan(),
            .success_border_fg = Color.green(),
            .warning_border_fg = Color.yellow(),
            .err_border_fg = Color.red(),
        };
    }

    pub fn deinit(self: *Toast) void {
        self.messages.deinit();
    }

    /// Push a notification.
    pub fn push(self: *Toast, text: []const u8, level: Level, duration_ms: u64, current_ns: u64) !void {
        try self.messages.append(.{
            .text = text,
            .level = level,
            .created_ns = current_ns,
            .duration_ms = duration_ms,
            .dismissable = true,
        });
    }

    /// Push a persistent notification (no auto-dismiss).
    pub fn pushPersistent(self: *Toast, text: []const u8, level: Level, current_ns: u64) !void {
        try self.messages.append(.{
            .text = text,
            .level = level,
            .created_ns = current_ns,
            .duration_ms = 0, // 0 = no auto-dismiss
            .dismissable = true,
        });
    }

    /// Dismiss the most recent notification.
    pub fn dismiss(self: *Toast) void {
        if (self.messages.items.len > 0) {
            _ = self.messages.pop();
        }
    }

    /// Dismiss all notifications.
    pub fn dismissAll(self: *Toast) void {
        self.messages.clearRetainingCapacity();
    }

    /// Remove expired notifications.
    pub fn update(self: *Toast, current_ns: u64) void {
        var i: usize = 0;
        while (i < self.messages.items.len) {
            const msg = self.messages.items[i];
            if (msg.duration_ms == 0) {
                // Persistent - don't auto-dismiss
                i += 1;
                continue;
            }
            const elapsed_ms = (current_ns -| msg.created_ns) / std.time.ns_per_ms;
            if (elapsed_ms >= msg.duration_ms) {
                _ = self.messages.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Check if there are any active notifications.
    pub fn hasMessages(self: *const Toast) bool {
        return self.messages.items.len > 0;
    }

    /// Count of active messages.
    pub fn count(self: *const Toast) usize {
        return self.messages.items.len;
    }

    /// Render notifications as a vertical stack.
    pub fn view(self: *const Toast, allocator: std.mem.Allocator, current_ns: u64) ![]const u8 {
        if (self.messages.items.len == 0) {
            return try allocator.dupe(u8, "");
        }

        var result = std.array_list.Managed(u8).init(allocator);

        const visible_count = @min(self.messages.items.len, self.max_visible);

        // Determine which messages to show based on stack order
        const total = self.messages.items.len;
        var indices = std.array_list.Managed(usize).init(allocator);

        switch (self.stack_order) {
            .newest_first => {
                var i: usize = 0;
                while (i < visible_count) : (i += 1) {
                    try indices.append(total - 1 - i);
                }
            },
            .oldest_first => {
                const start = if (total > self.max_visible) total - self.max_visible else 0;
                var i: usize = start;
                while (i < start + visible_count) : (i += 1) {
                    try indices.append(i);
                }
            },
        }

        for (indices.items, 0..) |idx, render_idx| {
            if (render_idx > 0) try result.append('\n');

            const msg = self.messages.items[idx];
            const toast_str = try self.renderSingleToast(allocator, msg, current_ns);
            try result.appendSlice(toast_str);
        }

        // Show overflow indicator
        if (total > self.max_visible) {
            try result.append('\n');
            const overflow_text = try std.fmt.allocPrint(allocator, "  +{d} more", .{total - self.max_visible});
            var dim_style = style_mod.Style{};
            dim_style = dim_style.fg(Color.gray(10));
            dim_style = dim_style.inline_style(true);
            const styled = try dim_style.render(allocator, overflow_text);
            try result.appendSlice(styled);
        }

        return result.toOwnedSlice();
    }

    /// Render for positioned display within a terminal.
    pub fn viewPositioned(self: *const Toast, allocator: std.mem.Allocator, term_width: usize, term_height: usize, current_ns: u64) ![]const u8 {
        const toast_content = try self.view(allocator, current_ns);
        if (toast_content.len == 0) return toast_content;

        const content_width = measure.maxLineWidth(toast_content);
        const content_height = measure.height(toast_content);

        const place_mod = @import("../layout/place.zig");

        const hpos: f32 = switch (self.position) {
            .top_left, .bottom_left => 0.0,
            .top_center, .bottom_center => 0.5,
            .top_right, .bottom_right => 1.0,
        };
        const vpos: f32 = switch (self.position) {
            .top_left, .top_center, .top_right => 0.0,
            .bottom_left, .bottom_center, .bottom_right => 1.0,
        };

        _ = content_width;
        _ = content_height;

        return place_mod.placeFloat(allocator, term_width, term_height, hpos, vpos, toast_content);
    }

    fn renderSingleToast(self: *const Toast, allocator: std.mem.Allocator, msg: ToastMessage, current_ns: u64) ![]const u8 {
        const active_style = self.styleForLevel(msg.level);

        var line = std.array_list.Managed(u8).init(allocator);

        // Icon
        if (self.show_icons) {
            const icon = switch (msg.level) {
                .info => self.info_icon,
                .success => self.success_icon,
                .warning => self.warning_icon,
                .err => self.err_icon,
            };
            const styled_icon = try active_style.render(allocator, icon);
            try line.appendSlice(styled_icon);
        }

        // Text
        const styled_text = try active_style.render(allocator, msg.text);
        try line.appendSlice(styled_text);

        // Countdown
        if (self.show_countdown and msg.duration_ms > 0) {
            const elapsed_ms = (current_ns -| msg.created_ns) / std.time.ns_per_ms;
            const remaining = if (elapsed_ms < msg.duration_ms) msg.duration_ms - elapsed_ms else 0;
            const remaining_sec = remaining / 1000;
            const countdown = try std.fmt.allocPrint(allocator, " ({d}s)", .{remaining_sec});
            var dim_style = style_mod.Style{};
            dim_style = dim_style.fg(Color.gray(10));
            dim_style = dim_style.inline_style(true);
            const styled_cd = try dim_style.render(allocator, countdown);
            try line.appendSlice(styled_cd);
        }

        const line_content = try line.toOwnedSlice();

        if (!self.show_border) {
            return line_content;
        }

        // Wrap in border
        var box_style = style_mod.Style{};
        box_style = box_style.borderAll(self.border_chars);
        box_style = box_style.borderForeground(self.borderColorForLevel(msg.level));
        box_style = box_style.paddingLeft(1).paddingRight(1);
        box_style = box_style.inline_style(false);

        return box_style.render(allocator, line_content);
    }

    fn styleForLevel(self: *const Toast, level: Level) style_mod.Style {
        return switch (level) {
            .info => self.info_style,
            .success => self.success_style,
            .warning => self.warning_style,
            .err => self.err_style,
        };
    }

    fn borderColorForLevel(self: *const Toast, level: Level) Color {
        return switch (level) {
            .info => self.info_border_fg,
            .success => self.success_border_fg,
            .warning => self.warning_border_fg,
            .err => self.err_border_fg,
        };
    }
};
