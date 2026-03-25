//! ZigZag Theming Example
//! Demonstrates switching between theme palettes at runtime.

const std = @import("std");
const zz = @import("zigzag");

const ThemeChoice = enum {
    default_dark,
    default_light,
    catppuccin_mocha,
    catppuccin_latte,
    dracula,
    nord,
    high_contrast,
};

const theme_names = [_][]const u8{
    "Default Dark",
    "Default Light",
    "Catppuccin Mocha",
    "Catppuccin Latte",
    "Dracula",
    "Nord",
    "High Contrast",
};

const Model = struct {
    current_theme: ThemeChoice,
    active_theme: zz.Theme,
    progress_val: f64,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.current_theme = .default_dark;
        self.active_theme = zz.Theme.fromPalette(zz.Palette.default_dark);
        self.progress_val = 35;
        return .{ .every = 100_000_000 };
    }

    fn getPalette(choice: ThemeChoice) zz.Palette {
        return switch (choice) {
            .default_dark => zz.Palette.default_dark,
            .default_light => zz.Palette.default_light,
            .catppuccin_mocha => zz.Palette.catppuccin_mocha,
            .catppuccin_latte => zz.Palette.catppuccin_latte,
            .dracula => zz.Palette.dracula,
            .nord => zz.Palette.nord,
            .high_contrast => zz.Palette.high_contrast,
        };
    }

    fn nextTheme(self: *Model) void {
        const idx = @intFromEnum(self.current_theme);
        const next = if (idx + 1 < theme_names.len) idx + 1 else 0;
        self.current_theme = @enumFromInt(next);
        self.active_theme = zz.Theme.fromPalette(getPalette(self.current_theme));
    }

    fn prevTheme(self: *Model) void {
        const idx = @intFromEnum(self.current_theme);
        const prev = if (idx > 0) idx - 1 else theme_names.len - 1;
        self.current_theme = @enumFromInt(prev);
        self.active_theme = zz.Theme.fromPalette(getPalette(self.current_theme));
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'n' => self.nextTheme(),
                        'p' => self.prevTheme(),
                        else => {},
                    },
                    .right => self.nextTheme(),
                    .left => self.prevTheme(),
                    .escape => return .quit,
                    else => {},
                }
            },
            .tick => {
                self.progress_val += 0.5;
                if (self.progress_val > 100) self.progress_val = 0;
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const t = &self.active_theme;
        const p = &t.palette;

        // Title
        const title_style = zz.Theme.boldStyleWith(p.primary);
        const title = title_style.render(ctx.allocator, "Theme Preview") catch "Theme Preview";

        // Theme name
        const name_style = zz.Theme.boldStyleWith(p.accent);
        const theme_name = name_style.render(ctx.allocator, theme_names[@intFromEnum(self.current_theme)]) catch "?";
        const theme_line = std.fmt.allocPrint(ctx.allocator, "Current: {s}", .{theme_name}) catch "?";

        // Color swatches
        const primary_s = zz.Theme.boldStyleWith(p.primary).render(ctx.allocator, "██ Primary") catch "";
        const secondary_s = zz.Theme.boldStyleWith(p.secondary).render(ctx.allocator, "██ Secondary") catch "";
        const accent_s = zz.Theme.boldStyleWith(p.accent).render(ctx.allocator, "██ Accent") catch "";
        const success_s = zz.Theme.styleWith(p.success).render(ctx.allocator, "██ Success") catch "";
        const warning_s = zz.Theme.styleWith(p.warning).render(ctx.allocator, "██ Warning") catch "";
        const danger_s = zz.Theme.styleWith(p.danger).render(ctx.allocator, "██ Danger") catch "";
        const info_s = zz.Theme.styleWith(p.info).render(ctx.allocator, "██ Info") catch "";

        // Text styles
        const fg_s = zz.Theme.styleWith(p.foreground).render(ctx.allocator, "Foreground text") catch "";
        const muted_s = zz.Theme.styleWith(p.muted).render(ctx.allocator, "Muted text") catch "";
        const subtle_s = zz.Theme.styleWith(p.subtle).render(ctx.allocator, "Subtle text") catch "";

        // Border preview
        var box_style = zz.Style{};
        box_style = box_style.borderAll(zz.Border.rounded);
        box_style = box_style.borderForeground(p.border_focus);
        box_style = box_style.paddingAll(1);
        box_style = box_style.fg(p.foreground);
        const box_content = std.fmt.allocPrint(ctx.allocator, "{s}\n{s}\n{s}", .{ fg_s, muted_s, subtle_s }) catch "?";
        const bordered = box_style.render(ctx.allocator, box_content) catch box_content;

        // Progress bar using theme colors
        var prog = zz.Progress.init();
        prog.setValue(self.progress_val);
        prog.width = 30;
        var full_s = zz.Style{};
        full_s = full_s.fg(p.primary);
        full_s = full_s.inline_style(true);
        prog.full_style = full_s;
        var empty_s = zz.Style{};
        empty_s = empty_s.fg(p.subtle);
        empty_s = empty_s.inline_style(true);
        prog.empty_style = empty_s;
        const prog_view = prog.view(ctx.allocator) catch "error";

        // Help
        const help_style = zz.Theme.styleWith(p.muted);
        const help = help_style.render(ctx.allocator, "Left/Right or n/p: switch theme | q: quit") catch "";

        return std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n{s}\n\n{s}  {s}  {s}\n{s}  {s}  {s}  {s}\n\n{s}\n\nProgress: {s}\n\n{s}",
            .{ title, theme_line, primary_s, secondary_s, accent_s, success_s, warning_s, danger_s, info_s, bordered, prog_view, help },
        ) catch "Error";
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
