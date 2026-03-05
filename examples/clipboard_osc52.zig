//! ZigZag OSC 52 Clipboard Example
//! Demonstrates outbound clipboard writes with configurable OSC 52 options.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    status: []const u8,
    status_buf: [320]u8,
    terminator: zz.OscTerminator,
    passthrough: zz.Osc52Passthrough,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{
            .status = "Ready. Press 'c' to copy to clipboard.",
            .status_buf = undefined,
            .terminator = .bel,
            .passthrough = .auto,
        };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .escape => return .quit,
                .char => |c| switch (c) {
                    'q' => return .quit,
                    't' => {
                        self.terminator = switch (self.terminator) {
                            .bel => .st,
                            .st => .bel,
                        };
                        self.setStatus("Terminator set to {s}", .{self.terminatorName()});
                    },
                    'p' => {
                        self.passthrough = switch (self.passthrough) {
                            .auto => .none,
                            .none => .tmux,
                            .tmux => .dcs,
                            .dcs => .auto,
                        };
                        self.setStatus("Passthrough set to {s}", .{self.passthroughName()});
                    },
                    'c' => self.copyWith(ctx, "Copied via default target (clipboard)", null),
                    '1' => self.copyWith(ctx, "Copied to target=c (clipboard)", .clipboard),
                    '2' => self.copyWith(ctx, "Copied to target=p (primary)", .primary),
                    '3' => self.copyWith(ctx, "Copied to target=q (secondary)", .secondary),
                    '4' => self.copyWith(ctx, "Copied to target=s (select)", .select),
                    else => {},
                },
                else => {},
            },
        }
        return .none;
    }

    fn copyWith(self: *Model, ctx: *zz.Context, text: []const u8, target: ?zz.Osc52Target) void {
        const result = if (target) |t|
            ctx.setClipboardWithOptions(text, .{
                .target = t,
                .terminator = self.terminator,
                .passthrough = self.passthrough,
            }) catch false
        else
            ctx.setClipboardWithOptions(text, .{
                .terminator = self.terminator,
                .passthrough = self.passthrough,
            }) catch false;

        if (result) {
            self.setStatus("Sent: \"{s}\"", .{text});
        } else {
            self.setStatus("Clipboard write rejected (disabled / guardrail / terminal policy)", .{});
        }
    }

    fn setStatus(self: *Model, comptime fmt: []const u8, args: anytype) void {
        self.status = std.fmt.bufPrint(&self.status_buf, fmt, args) catch "status error";
    }

    fn terminatorName(self: *const Model) []const u8 {
        return switch (self.terminator) {
            .bel => "BEL",
            .st => "ST",
        };
    }

    fn passthroughName(self: *const Model) []const u8 {
        return switch (self.passthrough) {
            .auto => "auto",
            .none => "none",
            .tmux => "tmux",
            .dcs => "dcs",
        };
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan());
        title_style = title_style.inline_style(true);

        var info_style = zz.Style{};
        info_style = info_style.fg(zz.Color.gray(16));
        info_style = info_style.inline_style(true);

        var hint_style = zz.Style{};
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);

        const title = title_style.render(ctx.allocator, "OSC 52 Clipboard Demo") catch "OSC 52 Clipboard Demo";
        const mode_line = std.fmt.allocPrint(ctx.allocator, "terminator={s}  passthrough={s}", .{
            self.terminatorName(),
            self.passthroughName(),
        }) catch "";
        const mode = info_style.render(ctx.allocator, mode_line) catch mode_line;
        const status = info_style.render(ctx.allocator, self.status) catch self.status;
        const hints = hint_style.render(ctx.allocator, "c copy(default)  1/2/3/4 target(c/p/q/s)  t terminator  p passthrough  q quit") catch "";

        const content = std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}\n{s}\n\n{s}", .{
            title,
            mode,
            status,
            hints,
        }) catch "render error";

        return zz.place.place(ctx.allocator, ctx.width, ctx.height, .center, .middle, content) catch content;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).initWithOptions(gpa.allocator(), .{
        .title = "ZigZag OSC 52 Clipboard",
        .osc52 = .{
            .enabled = true,
            .target = .clipboard,
            .terminator = .bel,
            .passthrough = .auto,
            .max_bytes = 256 * 1024,
        },
    });
    defer program.deinit();

    try program.run();
}
