//! Tooltip component for displaying contextual hints near a target position.
//!
//! ## Quick Start
//!
//! ```zig
//! // Create a tooltip
//! var tip = Tooltip.init("Save the current document");
//!
//! // Position it relative to a target
//! tip.target_x = 10;
//! tip.target_y = 5;
//! tip.placement = .bottom;
//! tip.show();
//!
//! // In your view function:
//! const output = try tip.render(allocator, term_width, term_height);
//! ```
//!
//! ## Placements
//!
//! - `.top` — above the target, arrow pointing down
//! - `.bottom` — below the target, arrow pointing up
//! - `.left` — to the left of the target, arrow pointing right
//! - `.right` — to the right of the target, arrow pointing left
//!
//! ## Presets
//!
//! - `Tooltip.init(text)` — simple tooltip with default style
//! - `Tooltip.titled(title, text)` — tooltip with a bold title line
//! - `Tooltip.help(text)` — dim, italic help-style tooltip
//! - `Tooltip.shortcut(label, key)` — "Label  Ctrl+S" style tooltip

const std = @import("std");
const style_mod = @import("../style/style.zig");
const border_mod = @import("../style/border.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub const Tooltip = struct {
    // ── State ──────────────────────────────────────────────────────────

    visible: bool = false,

    // ── Content ────────────────────────────────────────────────────────

    text: []const u8 = "",
    title: ?[]const u8 = null,

    // ── Position ──────────────────────────────────────────────────────

    /// X coordinate of the target element (display column).
    target_x: usize = 0,
    /// Y coordinate of the target element (display row).
    target_y: usize = 0,
    /// Width of the target element (used for centering arrows).
    target_width: usize = 1,
    /// Where to place the tooltip relative to the target.
    placement: Placement = .bottom,
    /// Gap between tooltip and target (in cells).
    gap: usize = 0,

    // ── Sizing ─────────────────────────────────────────────────────────

    /// Maximum width of the tooltip content area (excluding border/padding).
    max_width: usize = 40,
    /// Padding inside the tooltip box.
    padding: Padding = .{ .top = 0, .right = 1, .bottom = 0, .left = 1 },

    // ── Styling ────────────────────────────────────────────────────────

    border_chars: border_mod.BorderChars = border_mod.Border.rounded,
    border_fg: Color = Color.gray(14),
    content_bg: Color = .none,
    text_style: style_mod.Style = makeStyle(.{ .fg_color = Color.gray(20) }),
    title_style: style_mod.Style = makeStyle(.{ .bold_v = true, .fg_color = Color.white() }),

    /// Show an arrow pointing from tooltip toward the target.
    show_arrow: bool = true,
    /// Color of the arrow character.
    arrow_fg: Color = Color.gray(14),
    /// Custom arrow characters per direction (what's shown when the tooltip
    /// is placed in that direction). Set to "" to hide a specific arrow.
    arrow_up: []const u8 = "▲",
    arrow_down: []const u8 = "▼",
    arrow_left: []const u8 = "◀",
    arrow_right: []const u8 = "▶",

    // ── Types ──────────────────────────────────────────────────────────

    pub const Placement = enum { top, bottom, left, right };

    pub const Padding = struct {
        top: u16 = 0,
        right: u16 = 0,
        bottom: u16 = 0,
        left: u16 = 0,

        pub fn all(n: u16) Padding {
            return .{ .top = n, .right = n, .bottom = n, .left = n };
        }

        pub fn symmetric(vert: u16, horiz: u16) Padding {
            return .{ .top = vert, .right = horiz, .bottom = vert, .left = horiz };
        }
    };

    // ── Preset Constructors ────────────────────────────────────────────

    /// Simple tooltip with text content.
    pub fn init(text: []const u8) Tooltip {
        return .{ .text = text };
    }

    /// Tooltip with a bold title line above the text.
    pub fn titled(title_text: []const u8, body: []const u8) Tooltip {
        return .{
            .text = body,
            .title = title_text,
        };
    }

    /// Help-style tooltip with dim italic text.
    pub fn help(text: []const u8) Tooltip {
        return .{
            .text = text,
            .text_style = makeStyle(.{ .dim_v = true, .italic_v = true, .fg_color = Color.gray(16) }),
            .border_fg = Color.gray(10),
            .arrow_fg = Color.gray(10),
        };
    }

    /// Shortcut tooltip showing "Label  Key".
    pub fn shortcut(label: []const u8, key: []const u8) Tooltip {
        return .{
            .text = key,
            .title = label,
            .title_style = makeStyle(.{ .fg_color = Color.gray(18) }),
            .text_style = makeStyle(.{ .bold_v = true, .fg_color = Color.cyan() }),
        };
    }

    // ── State Management ───────────────────────────────────────────────

    pub fn show(self: *Tooltip) void {
        self.visible = true;
    }

    pub fn hide(self: *Tooltip) void {
        self.visible = false;
    }

    pub fn toggle(self: *Tooltip) void {
        self.visible = !self.visible;
    }

    pub fn isVisible(self: *const Tooltip) bool {
        return self.visible;
    }

    // ── Rendering ──────────────────────────────────────────────────────

    /// Render the tooltip box (no positioning). Returns the box string.
    pub fn renderBox(self: *const Tooltip, allocator: std.mem.Allocator) ![]const u8 {
        const bc = self.border_chars;

        // Compute content lines
        var content_lines = std.array_list.Managed([]const u8).init(allocator);
        defer content_lines.deinit();

        if (self.title) |t| {
            try content_lines.append(t);
        }

        var text_iter = std.mem.splitScalar(u8, self.text, '\n');
        while (text_iter.next()) |line| {
            try content_lines.append(line);
        }

        // Compute inner width
        var max_content_w: usize = 0;
        for (content_lines.items) |line| {
            max_content_w = @max(max_content_w, measure.width(line));
        }
        max_content_w = @min(max_content_w, self.max_width);

        const pad_h: usize = @as(usize, self.padding.left) + @as(usize, self.padding.right);
        const inner_w: usize = max_content_w + pad_h;

        // Inline styles
        var bdr_s = style_mod.Style{};
        bdr_s = bdr_s.fg(self.border_fg).inline_style(true);
        if (!self.content_bg.isNone()) bdr_s = bdr_s.bg(self.content_bg);

        var pad_s = style_mod.Style{};
        pad_s = pad_s.inline_style(true);
        if (!self.content_bg.isNone()) pad_s = pad_s.bg(self.content_bg);

        var result = std.array_list.Managed(u8).init(allocator);
        const writer = result.writer();

        // ── Top border ──
        try writer.writeAll(try bdr_s.render(allocator, bc.top_left));
        try writer.writeAll(try repeatStr(allocator, bdr_s, bc.horizontal, inner_w));
        try writer.writeAll(try bdr_s.render(allocator, bc.top_right));

        const styled_left = try bdr_s.render(allocator, bc.vertical);
        const styled_right = try bdr_s.render(allocator, bc.vertical);

        // ── Top padding ──
        for (0..self.padding.top) |_| {
            try writer.writeByte('\n');
            try writeEmptyLine(allocator, writer, styled_left, styled_right, pad_s, inner_w);
        }

        // ── Content lines ──
        for (content_lines.items, 0..) |line, idx| {
            try writer.writeByte('\n');
            try writer.writeAll(styled_left);
            try writer.writeAll(try pad_s.render(allocator, try nSpaces(allocator, self.padding.left)));

            // Pick style: title or body
            const is_title_line = self.title != null and idx == 0;
            var line_style = if (is_title_line) self.title_style else self.text_style;
            line_style = line_style.inline_style(true);
            if (!self.content_bg.isNone() and line_style.background.isNone()) {
                line_style = line_style.bg(self.content_bg);
            }
            try writer.writeAll(try line_style.render(allocator, line));

            const line_w = measure.width(line);
            const fill: usize = if (max_content_w > line_w) max_content_w - line_w else 0;
            try writer.writeAll(try pad_s.render(allocator, try nSpaces(allocator, fill + self.padding.right)));
            try writer.writeAll(styled_right);
        }

        // ── Bottom padding ──
        for (0..self.padding.bottom) |_| {
            try writer.writeByte('\n');
            try writeEmptyLine(allocator, writer, styled_left, styled_right, pad_s, inner_w);
        }

        // ── Bottom border ──
        try writer.writeByte('\n');
        try writer.writeAll(try bdr_s.render(allocator, bc.bottom_left));
        try writer.writeAll(try repeatStr(allocator, bdr_s, bc.horizontal, inner_w));
        try writer.writeAll(try bdr_s.render(allocator, bc.bottom_right));

        return result.toOwnedSlice();
    }

    /// Render the tooltip positioned on a full-screen canvas.
    /// Returns empty string if not visible.
    pub fn render(self: *const Tooltip, allocator: std.mem.Allocator, term_width: usize, term_height: usize) ![]const u8 {
        if (!self.visible) return try allocator.dupe(u8, "");

        const box = try self.renderBox(allocator);
        const box_w = measure.maxLineWidth(box);
        const box_h = measure.height(box);

        // Compute arrow position and tooltip position
        const pos = self.computePosition(box_w, box_h, term_width, term_height);

        // Build full-screen output line by line
        var result = std.array_list.Managed(u8).init(allocator);
        const wr = result.writer();

        // Collect box lines
        var box_lines = std.array_list.Managed([]const u8).init(allocator);
        defer box_lines.deinit();
        var box_iter = std.mem.splitScalar(u8, box, '\n');
        while (box_iter.next()) |line| try box_lines.append(line);

        const is_horizontal = self.placement == .left or self.placement == .right;

        for (0..term_height) |row| {
            if (row > 0) try wr.writeByte('\n');

            const in_box = row >= pos.box_y and row < pos.box_y + box_h;
            const is_arrow_row = self.show_arrow and row == pos.arrow_y;

            if (in_box) {
                const box_line_idx = row - pos.box_y;
                const box_line = if (box_line_idx < box_lines.items.len) box_lines.items[box_line_idx] else "";
                // For left/right placement, include arrow on the same row as the box
                if (is_arrow_row and is_horizontal) {
                    try self.writeBoxRowWithSideArrow(allocator, wr, pos, box_line, term_width);
                } else {
                    try wr.writeAll(try nSpaces(allocator, pos.box_x));
                    try wr.writeAll(box_line);
                    const right = pos.box_x + measure.width(box_line);
                    if (right < term_width) try wr.writeAll(try nSpaces(allocator, term_width - right));
                }
            } else if (is_arrow_row) {
                // Top/bottom arrow on its own row
                try self.writeArrowOnlyRow(allocator, wr, pos, term_width);
            } else {
                try wr.writeAll(try nSpaces(allocator, term_width));
            }
        }

        return result.toOwnedSlice();
    }

    /// Render just the tooltip box with arrow, composited onto the given base content.
    /// Uses line-by-line splicing (same approach as Modal's viewWithBackdrop).
    pub fn overlay(self: *const Tooltip, allocator: std.mem.Allocator, base: []const u8, term_width: usize, term_height: usize) ![]const u8 {
        if (!self.visible) return try allocator.dupe(u8, base);

        const box = try self.renderBox(allocator);
        const box_w = measure.maxLineWidth(box);
        const box_h = measure.height(box);
        const pos = self.computePosition(box_w, box_h, term_width, term_height);

        // Collect box lines
        var box_lines = std.array_list.Managed([]const u8).init(allocator);
        defer box_lines.deinit();
        var box_iter = std.mem.splitScalar(u8, box, '\n');
        while (box_iter.next()) |line| try box_lines.append(line);

        // Collect base lines
        var base_lines = std.array_list.Managed([]const u8).init(allocator);
        defer base_lines.deinit();
        var base_iter = std.mem.splitScalar(u8, base, '\n');
        while (base_iter.next()) |line| try base_lines.append(line);

        var result = std.array_list.Managed(u8).init(allocator);
        const wr = result.writer();

        const is_horizontal = self.placement == .left or self.placement == .right;

        for (0..term_height) |row| {
            if (row > 0) try wr.writeByte('\n');

            const base_line = if (row < base_lines.items.len) base_lines.items[row] else "";
            const in_box = row >= pos.box_y and row < pos.box_y + box_h;
            const is_arrow_row = self.show_arrow and row == pos.arrow_y;

            if (in_box) {
                const box_line_idx = row - pos.box_y;
                const box_line = if (box_line_idx < box_lines.items.len) box_lines.items[box_line_idx] else "";
                if (is_arrow_row and is_horizontal) {
                    try self.writeSplicedBoxRowWithSideArrow(allocator, wr, pos, base_line, box_line, box_w, term_width);
                } else {
                    try self.writeSplicedBoxRow(allocator, wr, pos, base_line, box_line, box_w, term_width);
                }
            } else if (is_arrow_row) {
                try self.writeSplicedArrowRow(allocator, wr, pos, base_line, term_width);
            } else {
                try wr.writeAll(base_line);
            }
        }

        return result.toOwnedSlice();
    }

    // ── Position Computation ──────────────────────────────────────────

    const Position = struct {
        box_x: usize,
        box_y: usize,
        arrow_x: usize,
        arrow_y: usize,
    };

    fn computePosition(self: *const Tooltip, box_w: usize, box_h: usize, tw: usize, th: usize) Position {
        var pos: Position = .{ .box_x = 0, .box_y = 0, .arrow_x = 0, .arrow_y = 0 };

        const arrow_offset: usize = if (self.show_arrow) 1 else 0;

        switch (self.placement) {
            .bottom => {
                // Box below target
                pos.arrow_y = self.target_y + 1 + self.gap;
                pos.box_y = pos.arrow_y + arrow_offset;
                // Center horizontally on target
                const target_center = self.target_x + self.target_width / 2;
                pos.box_x = if (target_center >= box_w / 2) target_center - box_w / 2 else 0;
                pos.arrow_x = target_center;
            },
            .top => {
                // Box above target
                const total_h = box_h + arrow_offset;
                pos.box_y = if (self.target_y >= total_h + self.gap) self.target_y - total_h - self.gap else 0;
                pos.arrow_y = pos.box_y + box_h;
                const target_center = self.target_x + self.target_width / 2;
                pos.box_x = if (target_center >= box_w / 2) target_center - box_w / 2 else 0;
                pos.arrow_x = target_center;
            },
            .right => {
                // Box to the right of target
                pos.box_x = self.target_x + self.target_width + self.gap + arrow_offset;
                pos.arrow_x = self.target_x + self.target_width + self.gap;
                // Center vertically on target
                pos.box_y = if (self.target_y >= box_h / 2) self.target_y - box_h / 2 else 0;
                pos.arrow_y = self.target_y;
            },
            .left => {
                // Box to the left of target
                const total_w = box_w + arrow_offset;
                pos.box_x = if (self.target_x >= total_w + self.gap) self.target_x - total_w - self.gap else 0;
                pos.arrow_x = pos.box_x + box_w;
                pos.box_y = if (self.target_y >= box_h / 2) self.target_y - box_h / 2 else 0;
                pos.arrow_y = self.target_y;
            },
        }

        // Clamp to terminal bounds
        if (pos.box_x + box_w > tw) pos.box_x = if (tw >= box_w) tw - box_w else 0;
        if (pos.box_y + box_h > th) pos.box_y = if (th >= box_h) th - box_h else 0;
        if (pos.arrow_x >= tw) pos.arrow_x = tw -| 1;
        if (pos.arrow_y >= th) pos.arrow_y = th -| 1;

        return pos;
    }

    fn arrowChar(self: *const Tooltip) []const u8 {
        return switch (self.placement) {
            .bottom => self.arrow_up,
            .top => self.arrow_down,
            .left => self.arrow_right,
            .right => self.arrow_left,
        };
    }

    fn renderStyledArrow(self: *const Tooltip, allocator: std.mem.Allocator) ![]const u8 {
        const ch = self.arrowChar();
        if (ch.len == 0) return try allocator.dupe(u8, "");
        var arrow_s = style_mod.Style{};
        arrow_s = arrow_s.fg(self.arrow_fg).inline_style(true);
        return try arrow_s.render(allocator, ch);
    }

    fn arrowDisplayWidth(self: *const Tooltip) usize {
        const ch = self.arrowChar();
        if (ch.len == 0) return 0;
        return measure.width(ch);
    }

    // ── Render helpers (full-screen canvas) ────────────────────────────

    /// Arrow on its own row (top/bottom placement).
    fn writeArrowOnlyRow(self: *const Tooltip, allocator: std.mem.Allocator, writer: anytype, pos: Position, tw: usize) !void {
        try writer.writeAll(try nSpaces(allocator, pos.arrow_x));
        try writer.writeAll(try self.renderStyledArrow(allocator));
        const aw = self.arrowDisplayWidth();
        const used = pos.arrow_x + aw;
        if (used < tw) try writer.writeAll(try nSpaces(allocator, tw - used));
    }

    /// Box row that also has a side arrow (left/right placement).
    fn writeBoxRowWithSideArrow(self: *const Tooltip, allocator: std.mem.Allocator, writer: anytype, pos: Position, box_line: []const u8, tw: usize) !void {
        const box_line_w = measure.width(box_line);
        const aw = self.arrowDisplayWidth();
        const styled_arrow = try self.renderStyledArrow(allocator);

        if (self.placement == .right) {
            // Layout: [spaces] [arrow] [box_line] [spaces]
            try writer.writeAll(try nSpaces(allocator, pos.arrow_x));
            try writer.writeAll(styled_arrow);
            // box_x should be arrow_x + aw, but use pos.box_x
            const gap_between = if (pos.box_x > pos.arrow_x + aw) pos.box_x - pos.arrow_x - aw else 0;
            try writer.writeAll(try nSpaces(allocator, gap_between));
            try writer.writeAll(box_line);
            const used = pos.arrow_x + aw + gap_between + box_line_w;
            if (used < tw) try writer.writeAll(try nSpaces(allocator, tw - used));
        } else {
            // .left — Layout: [spaces] [box_line] [arrow] [spaces]
            try writer.writeAll(try nSpaces(allocator, pos.box_x));
            try writer.writeAll(box_line);
            const gap_between = if (pos.arrow_x > pos.box_x + box_line_w) pos.arrow_x - pos.box_x - box_line_w else 0;
            try writer.writeAll(try nSpaces(allocator, gap_between));
            try writer.writeAll(styled_arrow);
            const used = pos.box_x + box_line_w + gap_between + aw;
            if (used < tw) try writer.writeAll(try nSpaces(allocator, tw - used));
        }
    }

    // ── Render helpers (overlay/splice) ────────────────────────────────

    /// Splice arrow-only row onto base line (top/bottom placement).
    fn writeSplicedArrowRow(self: *const Tooltip, allocator: std.mem.Allocator, writer: anytype, pos: Position, base_line: []const u8, tw: usize) !void {
        const aw = self.arrowDisplayWidth();

        // Left part from base
        const left = try truncateToWidth(allocator, base_line, pos.arrow_x);
        try writer.writeAll(left);
        const left_w = measure.width(left);
        if (left_w < pos.arrow_x) try writer.writeAll(try nSpaces(allocator, pos.arrow_x - left_w));

        // Arrow
        try writer.writeAll(try self.renderStyledArrow(allocator));

        // Right part from base
        const skip = pos.arrow_x + aw;
        const right = try skipColumns(allocator, base_line, skip);
        try writer.writeAll(right);
        const total_w = pos.arrow_x + aw + measure.width(right);
        if (total_w < tw) try writer.writeAll(try nSpaces(allocator, tw - total_w));
    }

    /// Splice box-only row onto base line.
    fn writeSplicedBoxRow(self: *const Tooltip, allocator: std.mem.Allocator, writer: anytype, pos: Position, base_line: []const u8, box_line: []const u8, box_w: usize, tw: usize) !void {
        _ = self;
        // Left part from base
        const left = try truncateToWidth(allocator, base_line, pos.box_x);
        try writer.writeAll(left);
        const left_w = measure.width(left);
        if (left_w < pos.box_x) try writer.writeAll(try nSpaces(allocator, pos.box_x - left_w));

        // Box line
        try writer.writeAll(box_line);
        const bw = measure.width(box_line);

        // Right part from base (skip box area)
        const skip = pos.box_x + @max(bw, box_w);
        const right = try skipColumns(allocator, base_line, skip);
        try writer.writeAll(right);
        const total_w = pos.box_x + bw + measure.width(right);
        if (total_w < tw) try writer.writeAll(try nSpaces(allocator, tw - total_w));
    }

    /// Splice box row + side arrow onto base line (left/right placement).
    fn writeSplicedBoxRowWithSideArrow(self: *const Tooltip, allocator: std.mem.Allocator, writer: anytype, pos: Position, base_line: []const u8, box_line: []const u8, box_w: usize, tw: usize) !void {
        const box_line_w = measure.width(box_line);
        const aw = self.arrowDisplayWidth();
        const styled_arrow = try self.renderStyledArrow(allocator);

        if (self.placement == .right) {
            // Layout: [base] [arrow] [box_line] [base]
            // The leftmost replaced column is arrow_x
            const splice_start = pos.arrow_x;
            const left = try truncateToWidth(allocator, base_line, splice_start);
            try writer.writeAll(left);
            const left_w = measure.width(left);
            if (left_w < splice_start) try writer.writeAll(try nSpaces(allocator, splice_start - left_w));

            try writer.writeAll(styled_arrow);
            const gap_between = if (pos.box_x > pos.arrow_x + aw) pos.box_x - pos.arrow_x - aw else 0;
            try writer.writeAll(try nSpaces(allocator, gap_between));
            try writer.writeAll(box_line);

            const splice_end = pos.box_x + @max(box_line_w, box_w);
            const right = try skipColumns(allocator, base_line, splice_end);
            try writer.writeAll(right);
            const total_w = splice_start + aw + gap_between + box_line_w + measure.width(right);
            if (total_w < tw) try writer.writeAll(try nSpaces(allocator, tw - total_w));
        } else {
            // .left — Layout: [base] [box_line] [arrow] [base]
            const splice_start = pos.box_x;
            const left = try truncateToWidth(allocator, base_line, splice_start);
            try writer.writeAll(left);
            const left_w = measure.width(left);
            if (left_w < splice_start) try writer.writeAll(try nSpaces(allocator, splice_start - left_w));

            try writer.writeAll(box_line);
            const gap_between = if (pos.arrow_x > pos.box_x + box_line_w) pos.arrow_x - pos.box_x - box_line_w else 0;
            try writer.writeAll(try nSpaces(allocator, gap_between));
            try writer.writeAll(styled_arrow);

            const splice_end = pos.arrow_x + aw;
            const right = try skipColumns(allocator, base_line, splice_end);
            try writer.writeAll(right);
            const total_w = splice_start + box_line_w + gap_between + aw + measure.width(right);
            if (total_w < tw) try writer.writeAll(try nSpaces(allocator, tw - total_w));
        }
    }

    // ── Private Helpers ───────────────────────────────────────────────

    fn writeEmptyLine(allocator: std.mem.Allocator, writer: anytype, styled_left: []const u8, styled_right: []const u8, pad_s: style_mod.Style, inner_w: usize) !void {
        try writer.writeAll(styled_left);
        try writer.writeAll(try pad_s.render(allocator, try nSpaces(allocator, inner_w)));
        try writer.writeAll(styled_right);
    }

    fn repeatStr(allocator: std.mem.Allocator, s: style_mod.Style, str: []const u8, count: usize) ![]const u8 {
        if (count == 0 or str.len == 0) return try allocator.dupe(u8, "");
        const buf = try allocator.alloc(u8, str.len * count);
        for (0..count) |i| {
            @memcpy(buf[i * str.len ..][0..str.len], str);
        }
        return try s.render(allocator, buf);
    }

    fn nSpaces(allocator: std.mem.Allocator, count: anytype) ![]const u8 {
        const n: usize = switch (@typeInfo(@TypeOf(count))) {
            .int, .comptime_int => @intCast(count),
            else => count,
        };
        if (n == 0) return try allocator.dupe(u8, "");
        const buf = try allocator.alloc(u8, n);
        @memset(buf, ' ');
        return buf;
    }

    /// Truncate a string (potentially with ANSI) to at most `max_w` display columns.
    fn truncateToWidth(allocator: std.mem.Allocator, str: []const u8, max_w: usize) ![]const u8 {
        if (max_w == 0) return try allocator.dupe(u8, "");
        if (measure.width(str) <= max_w) return try allocator.dupe(u8, str);

        var buf = std.array_list.Managed(u8).init(allocator);
        var w: usize = 0;
        var i: usize = 0;
        var in_escape = false;
        var escape_bracket = false;

        while (i < str.len and w < max_w) {
            const c = str[i];

            if (c == 0x1b) {
                in_escape = true;
                escape_bracket = false;
                try buf.append(c);
                i += 1;
                continue;
            }

            if (in_escape) {
                try buf.append(c);
                if (c == '[') {
                    escape_bracket = true;
                } else if (escape_bracket) {
                    if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        in_escape = false;
                        escape_bracket = false;
                    }
                } else {
                    in_escape = false;
                }
                i += 1;
                continue;
            }

            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch 1;
            if (i + byte_len <= str.len) {
                const cp = std.unicode.utf8Decode(str[i..][0..byte_len]) catch {
                    try buf.append(c);
                    w += 1;
                    i += 1;
                    continue;
                };
                const cw = @import("../unicode.zig").charWidth(cp);
                if (w + cw > max_w) break;
                try buf.appendSlice(str[i..][0..byte_len]);
                w += cw;
                i += byte_len;
            } else {
                try buf.append(c);
                w += 1;
                i += 1;
            }
        }

        return buf.toOwnedSlice();
    }

    /// Skip the first `skip_cols` display columns and return the rest of the string.
    fn skipColumns(allocator: std.mem.Allocator, str: []const u8, skip_cols: usize) ![]const u8 {
        var w: usize = 0;
        var i: usize = 0;
        var in_escape = false;
        var escape_bracket = false;

        while (i < str.len and w < skip_cols) {
            const c = str[i];

            if (c == 0x1b) {
                in_escape = true;
                escape_bracket = false;
                i += 1;
                continue;
            }

            if (in_escape) {
                if (c == '[') {
                    escape_bracket = true;
                } else if (escape_bracket) {
                    if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        in_escape = false;
                        escape_bracket = false;
                    }
                } else {
                    in_escape = false;
                }
                i += 1;
                continue;
            }

            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch 1;
            if (i + byte_len <= str.len) {
                const cp = std.unicode.utf8Decode(str[i..][0..byte_len]) catch {
                    w += 1;
                    i += 1;
                    continue;
                };
                w += @import("../unicode.zig").charWidth(cp);
                i += byte_len;
            } else {
                w += 1;
                i += 1;
            }
        }

        if (i >= str.len) return try allocator.dupe(u8, "");
        return try allocator.dupe(u8, str[i..]);
    }

    // Comptime style builder
    const StyleOpts = struct {
        bold_v: ?bool = null,
        dim_v: ?bool = null,
        italic_v: ?bool = null,
        fg_color: Color = .none,
        bg_color: Color = .none,
    };

    fn makeStyle(opts: StyleOpts) style_mod.Style {
        var s = style_mod.Style{};
        if (opts.bold_v) |v| s.bold_attr = v;
        if (opts.dim_v) |v| s.dim_attr = v;
        if (opts.italic_v) |v| s.italic_attr = v;
        if (!opts.fg_color.isNone()) s.foreground = opts.fg_color;
        if (!opts.bg_color.isNone()) s.background = opts.bg_color;
        s.inline_mode = true;
        return s;
    }
};
