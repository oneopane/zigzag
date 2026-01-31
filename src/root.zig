//! ZigZag - A TUI library for Zig inspired by Bubble Tea and Lipgloss
//!
//! ZigZag provides a framework for building terminal user interfaces using
//! the Elm architecture (Model-Update-View pattern).
//!
//! ## Quick Start
//!
//! ```zig
//! const std = @import("std");
//! const zz = @import("zigzag");
//!
//! const Model = struct {
//!     count: i32,
//!
//!     pub const Msg = union(enum) {
//!         key: zz.msg.Key,
//!     };
//!
//!     pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
//!         self.* = .{ .count = 0 };
//!         return .none;
//!     }
//!
//!     pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
//!         switch (msg) {
//!             .key => |k| switch (k.key) {
//!                 .char => |c| if (c == 'q') return .quit,
//!                 .up => self.count += 1,
//!                 .down => self.count -= 1,
//!                 else => {},
//!             },
//!         }
//!         return .none;
//!     }
//!
//!     pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
//!         return std.fmt.allocPrint(ctx.allocator, "Count: {d}\n\nPress q to quit", .{self.count}) catch "Error";
//!     }
//! };
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     defer _ = gpa.deinit();
//!
//!     var program = try zz.Program(Model).init(gpa.allocator());
//!     defer program.deinit();
//!     try program.run();
//! }
//! ```

const std = @import("std");

// Core
pub const program = @import("core/program.zig");
pub const Program = program.Program;
pub const Cmd = program.Cmd;
pub const command = @import("core/command.zig");
pub const Context = @import("core/context.zig").Context;
pub const Options = @import("core/context.zig").Options;
pub const msg = @import("core/message.zig");

// Terminal
pub const terminal = @import("terminal/terminal.zig");
pub const Terminal = terminal.Terminal;
pub const ansi = terminal.ansi;
pub const screen = terminal.screen;

// Input
pub const input = struct {
    pub const keyboard = @import("input/keyboard.zig");
    pub const mouse = @import("input/mouse.zig");
    pub const keys = @import("input/keys.zig");
};
pub const Key = input.keys.Key;
pub const KeyEvent = input.keys.KeyEvent;
pub const Modifiers = input.keys.Modifiers;
pub const MouseEvent = input.mouse.MouseEvent;

// Style
pub const style = @import("style/style.zig");
pub const Style = style.Style;
pub const color = @import("style/color.zig");
pub const Color = color.Color;
pub const border = @import("style/border.zig");
pub const Border = border.Border;

// Layout
pub const layout = @import("layout/layout.zig");
pub const measure = @import("layout/measure.zig");
pub const join = @import("layout/join.zig");
pub const place = @import("layout/place.zig");

// Components
pub const components = struct {
    pub const TextInput = @import("components/text_input.zig").TextInput;
    pub const TextArea = @import("components/text_area.zig").TextArea;
    pub const List = @import("components/list.zig").List;
    pub const Viewport = @import("components/viewport.zig").Viewport;
    pub const Progress = @import("components/progress.zig").Progress;
    pub const Spinner = @import("components/spinner.zig").Spinner;
    pub const Table = @import("components/table.zig").Table;
    pub const Paginator = @import("components/paginator.zig").Paginator;
    pub const Help = @import("components/help.zig").Help;
    pub const Timer = @import("components/timer.zig").Timer;
    pub const FilePicker = @import("components/file_picker.zig").FilePicker;
};

// Re-export commonly used components at top level
pub const TextInput = components.TextInput;
pub const TextArea = components.TextArea;
pub const List = components.List;
pub const Viewport = components.Viewport;
pub const Progress = components.Progress;
pub const Spinner = components.Spinner;
pub const Table = components.Table;

// Utility functions
pub fn joinHorizontal(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return join.horizontal(allocator, .top, parts);
}

pub fn joinVertical(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return join.vertical(allocator, .left, parts);
}

pub fn width(str: []const u8) usize {
    return measure.width(str);
}

pub fn height(str: []const u8) usize {
    return measure.height(str);
}

test {
    std.testing.refAllDecls(@This());
}
