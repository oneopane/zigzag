const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Palette default_dark has valid colors" {
    const p = zz.Palette.default_dark;
    // Check that colors are set (non-default)
    try testing.expect(p.primary.toRgb() != null);
    try testing.expect(p.foreground.toRgb() != null);
    try testing.expect(p.background.toRgb() != null);
}

test "Palette all presets are valid" {
    const palettes = [_]zz.Palette{
        zz.Palette.default_dark,
        zz.Palette.default_light,
        zz.Palette.catppuccin_mocha,
        zz.Palette.catppuccin_latte,
        zz.Palette.dracula,
        zz.Palette.nord,
        zz.Palette.high_contrast,
    };

    for (palettes) |p| {
        try testing.expect(p.primary.toRgb() != null);
        try testing.expect(p.danger.toRgb() != null);
    }
}

test "Theme fromPalette derives component themes" {
    const t = zz.Theme.fromPalette(zz.Palette.dracula);

    // Text theme inherits from palette
    const p = zz.Palette.dracula;
    try testing.expectEqual(p.foreground, t.text.text_fg);
    try testing.expectEqual(p.subtle, t.text.placeholder_fg);
    try testing.expectEqual(p.primary, t.text.prompt_fg);
    try testing.expectEqual(p.border_color, t.text.border_fg);
    try testing.expectEqual(p.border_focus, t.text.border_focus_fg);

    // List theme
    try testing.expectEqual(p.foreground, t.list.item_fg);
    try testing.expectEqual(p.primary, t.list.selected_fg);

    // Notification theme
    try testing.expectEqual(p.info, t.notification.info_fg);
    try testing.expectEqual(p.success, t.notification.success_fg);
    try testing.expectEqual(p.danger, t.notification.err_fg);
}

test "AdaptivePalette resolves correctly" {
    const adaptive = zz.AdaptivePalette.catppuccin;

    const dark = adaptive.resolve(true);
    try testing.expectEqual(zz.Palette.catppuccin_mocha.primary, dark.primary);

    const light = adaptive.resolve(false);
    try testing.expectEqual(zz.Palette.catppuccin_latte.primary, light.primary);
}

test "Theme styleWith creates inline style" {
    const s = zz.Theme.styleWith(zz.Color.red());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const rendered = try s.render(arena.allocator(), "hello");
    try testing.expect(rendered.len > 0);
}

test "Theme boldStyleWith creates bold inline style" {
    const s = zz.Theme.boldStyleWith(zz.Color.green());

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const rendered = try s.render(arena.allocator(), "bold");
    try testing.expect(rendered.len > 0);
}

test "Theme can be overridden per-component" {
    var t = zz.Theme.fromPalette(zz.Palette.nord);

    // Override list cursor color
    t.list.cursor_fg = zz.Color.red();
    try testing.expectEqual(zz.Color.red(), t.list.cursor_fg);

    // Other fields unchanged
    try testing.expectEqual(zz.Palette.nord.foreground, t.list.item_fg);
}
