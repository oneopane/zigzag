//! ZigZag Hello World Example
//! A minimal example showing the basic structure of a ZigZag application.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    /// The message type for this model
    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    /// Initialize the model
    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        _ = self;
        return .none;
    }

    /// Handle messages and update state
    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        _ = self;
        switch (msg) {
            .key => |k| {
                // Quit on 'q' or Escape
                switch (k.key) {
                    .char => |c| if (c == 'q') return .quit,
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    /// Render the view
    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        _ = self;

        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan());
        title_style = title_style.inline_style(true);

        var subtitle_style = zz.Style{};
        subtitle_style = subtitle_style.fg(zz.Color.gray(18));
        subtitle_style = subtitle_style.inline_style(true);

        var hint_style = zz.Style{};
        hint_style = hint_style.italic(true);
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);

        const title = title_style.render(ctx.allocator, "Hello, ZigZag!") catch "Hello, ZigZag!";
        const subtitle = subtitle_style.render(ctx.allocator, "A TUI library for Zig") catch "";
        const hint = hint_style.render(ctx.allocator, "Press 'q' to quit") catch "";

        // Get max width for centering
        const title_width = zz.measure.width(title);
        const subtitle_width = zz.measure.width(subtitle);
        const hint_width = zz.measure.width(hint);
        const max_width = @max(title_width, @max(subtitle_width, hint_width));

        // Center each element
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_subtitle = zz.place.place(ctx.allocator, max_width, 1, .center, .top, subtitle) catch subtitle;
        const centered_hint = zz.place.place(ctx.allocator, max_width, 1, .center, .top, hint) catch hint;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}",
            .{ centered_title, centered_subtitle, centered_hint },
        ) catch "Error rendering view";

        // Center in terminal
        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
