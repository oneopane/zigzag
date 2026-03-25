//! ZigZag Toast Example
//! Demonstrates the enhanced toast notification system with positioning and styles.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    toast: zz.Toast,
    msg_counter: usize,
    last_elapsed: u64,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.toast = zz.Toast.init(ctx.persistent_allocator);
        self.toast.position = .top_right;
        self.toast.show_countdown = true;
        self.msg_counter = 0;
        self.last_elapsed = 0;

        // Initial welcome toast
        self.toast.push("Welcome to the Toast demo!", .info, 5000, 0) catch {};

        return .{ .every = 100_000_000 };
    }

    pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .tick => {
                self.last_elapsed = ctx.elapsed;
                self.toast.update(ctx.elapsed);
            },
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        '1' => {
                            self.msg_counter += 1;
                            const text = std.fmt.allocPrint(ctx.persistent_allocator, "Info message #{d}", .{self.msg_counter}) catch "Info";
                            self.toast.push(text, .info, 3000, ctx.elapsed) catch {};
                        },
                        '2' => {
                            self.msg_counter += 1;
                            const text = std.fmt.allocPrint(ctx.persistent_allocator, "Success #{d}!", .{self.msg_counter}) catch "Success";
                            self.toast.push(text, .success, 3000, ctx.elapsed) catch {};
                        },
                        '3' => {
                            self.msg_counter += 1;
                            const text = std.fmt.allocPrint(ctx.persistent_allocator, "Warning #{d}", .{self.msg_counter}) catch "Warning";
                            self.toast.push(text, .warning, 4000, ctx.elapsed) catch {};
                        },
                        '4' => {
                            self.msg_counter += 1;
                            const text = std.fmt.allocPrint(ctx.persistent_allocator, "Error #{d}!", .{self.msg_counter}) catch "Error";
                            self.toast.push(text, .err, 5000, ctx.elapsed) catch {};
                        },
                        '5' => {
                            self.toast.pushPersistent("Persistent notification (press d to dismiss)", .info, ctx.elapsed) catch {};
                        },
                        'd' => self.toast.dismiss(),
                        'D' => self.toast.dismissAll(),
                        'b' => self.toast.show_border = !self.toast.show_border,
                        'i' => self.toast.show_icons = !self.toast.show_icons,
                        'c' => self.toast.show_countdown = !self.toast.show_countdown,
                        'p' => {
                            self.toast.position = switch (self.toast.position) {
                                .top_left => .top_center,
                                .top_center => .top_right,
                                .top_right => .bottom_right,
                                .bottom_right => .bottom_center,
                                .bottom_center => .bottom_left,
                                .bottom_left => .top_left,
                            };
                        },
                        's' => {
                            self.toast.stack_order = if (self.toast.stack_order == .newest_first) .oldest_first else .newest_first;
                        },
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.magenta());
        title_style = title_style.inline_style(true);
        const title = title_style.render(ctx.allocator, "Toast Notifications") catch "Toast";

        const pos_name: []const u8 = switch (self.toast.position) {
            .top_left => "top-left",
            .top_center => "top-center",
            .top_right => "top-right",
            .bottom_left => "bottom-left",
            .bottom_center => "bottom-center",
            .bottom_right => "bottom-right",
        };
        const order_name: []const u8 = if (self.toast.stack_order == .newest_first) "newest first" else "oldest first";

        var info_style = zz.Style{};
        info_style = info_style.fg(zz.Color.cyan());
        info_style = info_style.inline_style(true);
        const info = std.fmt.allocPrint(
            ctx.allocator,
            "Position: {s} | Order: {s} | Active: {d} | Borders: {s} | Icons: {s} | Countdown: {s}",
            .{
                pos_name,
                order_name,
                self.toast.count(),
                if (self.toast.show_border) "on" else "off",
                if (self.toast.show_icons) "on" else "off",
                if (self.toast.show_countdown) "on" else "off",
            },
        ) catch "?";
        const styled_info = info_style.render(ctx.allocator, info) catch info;

        var help_style = zz.Style{};
        help_style = help_style.fg(zz.Color.gray(12));
        help_style = help_style.inline_style(true);
        const help = help_style.render(ctx.allocator,
            \\1: info  2: success  3: warning  4: error  5: persistent
            \\d: dismiss  D: dismiss all  b: borders  i: icons  c: countdown
            \\p: cycle position  s: stack order  q: quit
        ) catch "";

        // Render toast notifications
        const toast_view = self.toast.viewPositioned(ctx.allocator, ctx.width, ctx.height -| 8, self.last_elapsed) catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n\n{s}\n\n{s}",
            .{ title, styled_info, help, toast_view },
        ) catch "Error";
    }

    pub fn deinit(self: *Model) void {
        self.toast.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var program = try zz.Program(Model).init(allocator);
    defer program.deinit();

    try program.run();
}
