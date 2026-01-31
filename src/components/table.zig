//! Table component for displaying tabular data.
//! Supports column headers, alignment, and styling.

const std = @import("std");
const style_mod = @import("../style/style.zig");
const border_mod = @import("../style/border.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");

pub fn Table(comptime num_cols: usize) type {
    return struct {
        allocator: std.mem.Allocator,

        // Data
        headers: [num_cols][]const u8,
        rows: std.array_list.Managed([num_cols][]const u8),

        // Appearance
        col_widths: [num_cols]?u16,
        col_aligns: [num_cols]Align,
        border_chars: border_mod.BorderChars,
        show_header: bool,
        show_border: bool,

        // Styling
        header_style: style_mod.Style,
        cell_style: style_mod.Style,
        border_style: style_mod.Style,
        alt_row_style: ?style_mod.Style,

        const Self = @This();

        pub const Align = enum {
            left,
            center,
            right,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .headers = .{""} ** num_cols,
                .rows = std.array_list.Managed([num_cols][]const u8).init(allocator),
                .col_widths = .{null} ** num_cols,
                .col_aligns = .{.left} ** num_cols,
                .border_chars = border_mod.Border.normal,
                .show_header = true,
                .show_border = true,
                .header_style = blk: {
                    var s = style_mod.Style{};
                    s = s.bold(true);
                    s = s.inline_style(true);
                    break :blk s;
                },
                .cell_style = blk: {
                    var s = style_mod.Style{};
                    s = s.inline_style(true);
                    break :blk s;
                },
                .border_style = blk: {
                    var s = style_mod.Style{};
                    s = s.fg(Color.gray(12));
                    s = s.inline_style(true);
                    break :blk s;
                },
                .alt_row_style = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }

        /// Set column headers
        pub fn setHeaders(self: *Self, headers: [num_cols][]const u8) void {
            self.headers = headers;
        }

        /// Add a row
        pub fn addRow(self: *Self, row: [num_cols][]const u8) !void {
            try self.rows.append(row);
        }

        /// Add multiple rows
        pub fn addRows(self: *Self, rows: []const [num_cols][]const u8) !void {
            try self.rows.appendSlice(rows);
        }

        /// Clear all rows
        pub fn clearRows(self: *Self) void {
            self.rows.clearRetainingCapacity();
        }

        /// Set column width
        pub fn setColumnWidth(self: *Self, col: usize, width: u16) void {
            if (col < num_cols) {
                self.col_widths[col] = width;
            }
        }

        /// Set column alignment
        pub fn setColumnAlign(self: *Self, col: usize, align_val: Align) void {
            if (col < num_cols) {
                self.col_aligns[col] = align_val;
            }
        }

        /// Set border style
        pub fn setBorder(self: *Self, border: border_mod.BorderChars) void {
            self.border_chars = border;
        }

        /// Calculate actual column widths
        fn calculateWidths(self: *const Self) [num_cols]usize {
            var widths: [num_cols]usize = .{0} ** num_cols;

            // Check headers
            for (0..num_cols) |i| {
                if (self.col_widths[i]) |w| {
                    widths[i] = w;
                } else {
                    widths[i] = @max(widths[i], measure.width(self.headers[i]));
                }
            }

            // Check rows
            for (self.rows.items) |row| {
                for (0..num_cols) |i| {
                    if (self.col_widths[i] == null) {
                        widths[i] = @max(widths[i], measure.width(row[i]));
                    }
                }
            }

            return widths;
        }

        /// Render the table
        pub fn view(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result = std.array_list.Managed(u8).init(allocator);
            const writer = result.writer();

            const widths = self.calculateWidths();

            // Top border
            if (self.show_border) {
                try self.writeBorderLine(writer, allocator, widths, .top);
                try writer.writeByte('\n');
            }

            // Header
            if (self.show_header) {
                try self.writeRow(writer, allocator, self.headers, widths, self.header_style);
                try writer.writeByte('\n');

                // Header separator
                if (self.show_border) {
                    try self.writeBorderLine(writer, allocator, widths, .middle);
                    try writer.writeByte('\n');
                }
            }

            // Data rows
            for (self.rows.items, 0..) |row, row_idx| {
                const row_style = if (self.alt_row_style != null and row_idx % 2 == 1)
                    self.alt_row_style.?
                else
                    self.cell_style;

                try self.writeRow(writer, allocator, row, widths, row_style);
                if (row_idx < self.rows.items.len - 1 or self.show_border) {
                    try writer.writeByte('\n');
                }
            }

            // Bottom border
            if (self.show_border) {
                try self.writeBorderLine(writer, allocator, widths, .bottom);
            }

            return result.toOwnedSlice();
        }

        fn writeRow(
            self: *const Self,
            writer: anytype,
            allocator: std.mem.Allocator,
            row: [num_cols][]const u8,
            widths: [num_cols]usize,
            row_style: style_mod.Style,
        ) !void {
            if (self.show_border) {
                const border_rendered = try self.border_style.render(allocator, self.border_chars.vertical);
                try writer.writeAll(border_rendered);
            }

            for (0..num_cols) |i| {
                if (i > 0 and self.show_border) {
                    const border_rendered = try self.border_style.render(allocator, self.border_chars.vertical);
                    try writer.writeAll(border_rendered);
                }

                try writer.writeByte(' ');

                const cell = row[i];
                const width = widths[i];
                const cell_width = measure.width(cell);
                const padding = if (width > cell_width) width - cell_width else 0;

                switch (self.col_aligns[i]) {
                    .left => {
                        const styled = try row_style.render(allocator, cell);
                        try writer.writeAll(styled);
                        for (0..padding) |_| try writer.writeByte(' ');
                    },
                    .center => {
                        const left_pad = padding / 2;
                        const right_pad = padding - left_pad;
                        for (0..left_pad) |_| try writer.writeByte(' ');
                        const styled = try row_style.render(allocator, cell);
                        try writer.writeAll(styled);
                        for (0..right_pad) |_| try writer.writeByte(' ');
                    },
                    .right => {
                        for (0..padding) |_| try writer.writeByte(' ');
                        const styled = try row_style.render(allocator, cell);
                        try writer.writeAll(styled);
                    },
                }

                try writer.writeByte(' ');
            }

            if (self.show_border) {
                const border_rendered = try self.border_style.render(allocator, self.border_chars.vertical);
                try writer.writeAll(border_rendered);
            }
        }

        const BorderPosition = enum { top, middle, bottom };

        fn writeBorderLine(
            self: *const Self,
            writer: anytype,
            allocator: std.mem.Allocator,
            widths: [num_cols]usize,
            pos: BorderPosition,
        ) !void {
            const left = switch (pos) {
                .top => self.border_chars.top_left,
                .middle => self.border_chars.middle_left,
                .bottom => self.border_chars.bottom_left,
            };
            const mid = switch (pos) {
                .top => self.border_chars.middle_top,
                .middle => self.border_chars.cross,
                .bottom => self.border_chars.middle_bottom,
            };
            const right = switch (pos) {
                .top => self.border_chars.top_right,
                .middle => self.border_chars.middle_right,
                .bottom => self.border_chars.bottom_right,
            };

            const left_styled = try self.border_style.render(allocator, left);
            try writer.writeAll(left_styled);

            for (0..num_cols) |i| {
                if (i > 0) {
                    const mid_styled = try self.border_style.render(allocator, mid);
                    try writer.writeAll(mid_styled);
                }

                const h_styled = try self.border_style.render(allocator, self.border_chars.horizontal);
                for (0..widths[i] + 2) |_| {
                    try writer.writeAll(h_styled);
                }
            }

            const right_styled = try self.border_style.render(allocator, right);
            try writer.writeAll(right_styled);
        }
    };
}

/// Create a table with dynamic column count
pub fn DynamicTable(allocator: std.mem.Allocator) DynamicTableType {
    return DynamicTableType.init(allocator);
}

pub const DynamicTableType = struct {
    allocator: std.mem.Allocator,
    headers: std.array_list.Managed([]const u8),
    rows: std.array_list.Managed(std.array_list.Managed([]const u8)),
    border_chars: border_mod.BorderChars,
    show_header: bool,
    show_border: bool,

    pub fn init(allocator: std.mem.Allocator) DynamicTableType {
        return .{
            .allocator = allocator,
            .headers = std.array_list.Managed([]const u8).init(allocator),
            .rows = std.array_list.Managed(std.array_list.Managed([]const u8)).init(allocator),
            .border_chars = border_mod.Border.normal,
            .show_header = true,
            .show_border = true,
        };
    }

    pub fn deinit(self: *DynamicTableType) void {
        self.headers.deinit();
        for (self.rows.items) |*row| {
            row.deinit();
        }
        self.rows.deinit();
    }

    pub fn setHeaders(self: *DynamicTableType, headers: []const []const u8) !void {
        self.headers.clearRetainingCapacity();
        try self.headers.appendSlice(headers);
    }

    pub fn addRow(self: *DynamicTableType, cells: []const []const u8) !void {
        var row = std.array_list.Managed([]const u8).init(self.allocator);
        try row.appendSlice(cells);
        try self.rows.append(row);
    }
};
