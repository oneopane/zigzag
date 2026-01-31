//! Style struct for terminal text styling (Lipgloss equivalent).
//! Provides a builder pattern for composing styles.

const std = @import("std");
const color_mod = @import("color.zig");
const border_mod = @import("border.zig");
const ansi = @import("../terminal/ansi.zig");
const measure = @import("../layout/measure.zig");

pub const Color = color_mod.Color;
pub const Border = border_mod.Border;
pub const BorderChars = border_mod.BorderChars;
pub const Sides = border_mod.Sides;

/// Padding/Margin specification
pub const Spacing = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn all(n: u16) Spacing {
        return .{ .top = n, .right = n, .bottom = n, .left = n };
    }

    pub fn symmetric(vert: u16, horiz: u16) Spacing {
        return .{ .top = vert, .right = horiz, .bottom = vert, .left = horiz };
    }

    pub fn horizontal(n: u16) Spacing {
        return .{ .left = n, .right = n };
    }

    pub fn vertical(n: u16) Spacing {
        return .{ .top = n, .bottom = n };
    }
};

/// Text alignment
pub const Align = enum {
    left,
    center,
    right,
};

/// Vertical alignment
pub const VAlign = enum {
    top,
    middle,
    bottom,
};

/// Style definition with builder pattern
pub const Style = struct {
    // Colors
    foreground: Color = .none,
    background: Color = .none,

    // Text attributes
    bold_attr: bool = false,
    dim_attr: bool = false,
    italic_attr: bool = false,
    underline_attr: bool = false,
    blink_attr: bool = false,
    reverse_attr: bool = false,
    strikethrough_attr: bool = false,

    // Spacing
    padding_val: Spacing = .{},
    margin_val: Spacing = .{},

    // Border
    border_style: BorderChars = Border.none,
    border_sides: Sides = Sides.none,
    border_fg: Color = .none,
    border_bg: Color = .none,

    // Size constraints
    width_val: ?u16 = null,
    height_val: ?u16 = null,
    max_width_val: ?u16 = null,
    max_height_val: ?u16 = null,

    // Alignment
    align_horizontal: Align = .left,
    align_vertical: VAlign = .top,

    // Inline (no newlines)
    inline_mode: bool = false,

    const Self = @This();

    // Color setters
    pub fn foreground_color(self: Self, c: Color) Self {
        var s = self;
        s.foreground = c;
        return s;
    }

    pub fn background_color(self: Self, c: Color) Self {
        var s = self;
        s.background = c;
        return s;
    }

    pub fn fg(self: Self, c: Color) Self {
        return self.foreground_color(c);
    }

    pub fn bg(self: Self, c: Color) Self {
        return self.background_color(c);
    }

    // Text attribute setters
    pub fn bold(self: Self, v: bool) Self {
        var s = self;
        s.bold_attr = v;
        return s;
    }

    pub fn dim(self: Self, v: bool) Self {
        var s = self;
        s.dim_attr = v;
        return s;
    }

    pub fn italic(self: Self, v: bool) Self {
        var s = self;
        s.italic_attr = v;
        return s;
    }

    pub fn underline(self: Self, v: bool) Self {
        var s = self;
        s.underline_attr = v;
        return s;
    }

    pub fn blink(self: Self, v: bool) Self {
        var s = self;
        s.blink_attr = v;
        return s;
    }

    pub fn reverse(self: Self, v: bool) Self {
        var s = self;
        s.reverse_attr = v;
        return s;
    }

    pub fn strikethrough(self: Self, v: bool) Self {
        var s = self;
        s.strikethrough_attr = v;
        return s;
    }

    // Spacing setters
    pub fn padding(self: Self, p: Spacing) Self {
        var s = self;
        s.padding_val = p;
        return s;
    }

    pub fn paddingAll(self: Self, n: u16) Self {
        return self.padding(Spacing.all(n));
    }

    pub fn paddingLeft(self: Self, n: u16) Self {
        var s = self;
        s.padding_val.left = n;
        return s;
    }

    pub fn paddingRight(self: Self, n: u16) Self {
        var s = self;
        s.padding_val.right = n;
        return s;
    }

    pub fn paddingTop(self: Self, n: u16) Self {
        var s = self;
        s.padding_val.top = n;
        return s;
    }

    pub fn paddingBottom(self: Self, n: u16) Self {
        var s = self;
        s.padding_val.bottom = n;
        return s;
    }

    pub fn margin(self: Self, m: Spacing) Self {
        var s = self;
        s.margin_val = m;
        return s;
    }

    pub fn marginAll(self: Self, n: u16) Self {
        return self.margin(Spacing.all(n));
    }

    pub fn marginLeft(self: Self, n: u16) Self {
        var s = self;
        s.margin_val.left = n;
        return s;
    }

    pub fn marginRight(self: Self, n: u16) Self {
        var s = self;
        s.margin_val.right = n;
        return s;
    }

    pub fn marginTop(self: Self, n: u16) Self {
        var s = self;
        s.margin_val.top = n;
        return s;
    }

    pub fn marginBottom(self: Self, n: u16) Self {
        var s = self;
        s.margin_val.bottom = n;
        return s;
    }

    // Border setters
    pub fn border(self: Self, chars: BorderChars, sides: Sides) Self {
        var s = self;
        s.border_style = chars;
        s.border_sides = sides;
        return s;
    }

    pub fn borderAll(self: Self, chars: BorderChars) Self {
        return self.border(chars, Sides.all);
    }

    pub fn borderForeground(self: Self, c: Color) Self {
        var s = self;
        s.border_fg = c;
        return s;
    }

    pub fn borderBackground(self: Self, c: Color) Self {
        var s = self;
        s.border_bg = c;
        return s;
    }

    // Size setters
    pub fn width(self: Self, w: u16) Self {
        var s = self;
        s.width_val = w;
        return s;
    }

    pub fn height(self: Self, h: u16) Self {
        var s = self;
        s.height_val = h;
        return s;
    }

    pub fn maxWidth(self: Self, w: u16) Self {
        var s = self;
        s.max_width_val = w;
        return s;
    }

    pub fn maxHeight(self: Self, h: u16) Self {
        var s = self;
        s.max_height_val = h;
        return s;
    }

    // Alignment setters
    pub fn alignH(self: Self, a: Align) Self {
        var s = self;
        s.align_horizontal = a;
        return s;
    }

    pub fn valign(self: Self, a: VAlign) Self {
        var s = self;
        s.align_vertical = a;
        return s;
    }

    // Inline mode
    pub fn inline_style(self: Self, v: bool) Self {
        var s = self;
        s.inline_mode = v;
        return s;
    }

    /// Inherit unset values from another style
    pub fn inherit(self: Self, other: Self) Self {
        var s = self;
        if (s.foreground == .none) s.foreground = other.foreground;
        if (s.background == .none) s.background = other.background;
        return s;
    }

    /// Render styled text
    pub fn render(self: Self, allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var result = std.array_list.Managed(u8).init(allocator);
        const writer = result.writer();

        // Calculate content dimensions
        const content_width = measure.width(text);
        const content_height = measure.height(text);

        // Apply size constraints
        var target_width = content_width;
        var target_height = content_height;

        if (self.width_val) |w| target_width = w;
        if (self.height_val) |h| target_height = h;
        if (self.max_width_val) |mw| target_width = @min(target_width, mw);
        if (self.max_height_val) |mh| target_height = @min(target_height, mh);

        // Add padding to target dimensions
        target_width += self.padding_val.left + self.padding_val.right;
        target_height += self.padding_val.top + self.padding_val.bottom;

        // Add border width
        if (self.border_sides.left) target_width += 1;
        if (self.border_sides.right) target_width += 1;
        if (self.border_sides.top) target_height += 1;
        if (self.border_sides.bottom) target_height += 1;

        // Write margin top
        for (0..self.margin_val.top) |_| {
            try writer.writeByte('\n');
        }

        // Build styled content
        try self.writeStyledContent(writer, text, target_width, target_height);

        // Write margin bottom
        for (0..self.margin_val.bottom) |_| {
            try writer.writeByte('\n');
        }

        return result.toOwnedSlice();
    }

    fn writeStyledContent(self: Self, writer: anytype, text: []const u8, target_width: usize, target_height: usize) !void {
        const inner_width = target_width -|
            self.padding_val.left -| self.padding_val.right -|
            @as(usize, if (self.border_sides.left) 1 else 0) -|
            @as(usize, if (self.border_sides.right) 1 else 0);

        const inner_height = target_height -|
            self.padding_val.top -| self.padding_val.bottom -|
            @as(usize, if (self.border_sides.top) 1 else 0) -|
            @as(usize, if (self.border_sides.bottom) 1 else 0);

        _ = inner_height;

        // Start style
        try self.writeStyleStart(writer);

        // Top border
        if (self.border_sides.top) {
            try self.writeMarginLeft(writer);
            try self.writeBorderColor(writer);
            if (self.border_sides.left) try writer.writeAll(self.border_style.top_left);
            for (0..inner_width + self.padding_val.left + self.padding_val.right) |_| {
                try writer.writeAll(self.border_style.horizontal);
            }
            if (self.border_sides.right) try writer.writeAll(self.border_style.top_right);
            try writer.writeAll(ansi.reset);
            if (!self.inline_mode) try writer.writeByte('\n');
        }

        // Padding top
        for (0..self.padding_val.top) |_| {
            try self.writeContentLine(writer, "", inner_width);
        }

        // Content lines
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            try self.writeContentLine(writer, line, inner_width);
        }

        // Padding bottom
        for (0..self.padding_val.bottom) |_| {
            try self.writeContentLine(writer, "", inner_width);
        }

        // Bottom border
        if (self.border_sides.bottom) {
            try self.writeMarginLeft(writer);
            try self.writeBorderColor(writer);
            if (self.border_sides.left) try writer.writeAll(self.border_style.bottom_left);
            for (0..inner_width + self.padding_val.left + self.padding_val.right) |_| {
                try writer.writeAll(self.border_style.horizontal);
            }
            if (self.border_sides.right) try writer.writeAll(self.border_style.bottom_right);
            try writer.writeAll(ansi.reset);
        }
    }

    fn writeContentLine(self: Self, writer: anytype, line: []const u8, inner_width: usize) !void {
        try self.writeMarginLeft(writer);

        // Left border
        if (self.border_sides.left) {
            try self.writeBorderColor(writer);
            try writer.writeAll(self.border_style.vertical);
            try writer.writeAll(ansi.reset);
        }

        // Start content style
        try self.writeStyleStart(writer);

        // Left padding
        for (0..self.padding_val.left) |_| {
            try writer.writeByte(' ');
        }

        // Content with alignment
        const line_width = measure.width(line);
        const content_pad = if (inner_width > line_width) inner_width - line_width else 0;

        switch (self.align_horizontal) {
            .left => {
                try writer.writeAll(line);
                for (0..content_pad) |_| {
                    try writer.writeByte(' ');
                }
            },
            .center => {
                const left_pad = content_pad / 2;
                const right_pad = content_pad - left_pad;
                for (0..left_pad) |_| {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(line);
                for (0..right_pad) |_| {
                    try writer.writeByte(' ');
                }
            },
            .right => {
                for (0..content_pad) |_| {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(line);
            },
        }

        // Right padding
        for (0..self.padding_val.right) |_| {
            try writer.writeByte(' ');
        }

        // Reset style
        try writer.writeAll(ansi.reset);

        // Right border
        if (self.border_sides.right) {
            try self.writeBorderColor(writer);
            try writer.writeAll(self.border_style.vertical);
            try writer.writeAll(ansi.reset);
        }

        if (!self.inline_mode) try writer.writeByte('\n');
    }

    fn writeMarginLeft(self: Self, writer: anytype) !void {
        for (0..self.margin_val.left) |_| {
            try writer.writeByte(' ');
        }
    }

    fn writeStyleStart(self: Self, writer: anytype) !void {
        if (self.bold_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.bold});
        if (self.dim_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.dim});
        if (self.italic_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.italic});
        if (self.underline_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.underline});
        if (self.blink_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.blink});
        if (self.reverse_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.reverse});
        if (self.strikethrough_attr) try writer.print(ansi.CSI ++ "{d}m", .{ansi.SGR.strikethrough});

        try self.foreground.writeFg(writer);
        try self.background.writeBg(writer);
    }

    fn writeBorderColor(self: Self, writer: anytype) !void {
        try self.border_fg.writeFg(writer);
        try self.border_bg.writeBg(writer);
    }

    /// Copy style
    pub fn copy(self: Self) Self {
        return self;
    }
};

/// Create a new empty style
pub fn newStyle() Style {
    return Style{};
}
