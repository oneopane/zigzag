const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");
const Tooltip = zz.Tooltip;

// ---------------------------------------------------------------------------
// Preset constructors
// ---------------------------------------------------------------------------

test "init — simple text tooltip" {
    const t = Tooltip.init("Hello");
    try testing.expectEqualStrings("Hello", t.text);
    try testing.expect(t.title == null);
    try testing.expect(!t.visible);
}

test "titled — tooltip with title" {
    const t = Tooltip.titled("Info", "Some detail");
    try testing.expectEqualStrings("Info", t.title.?);
    try testing.expectEqualStrings("Some detail", t.text);
}

test "help — dim italic preset" {
    const t = Tooltip.help("Press Enter to confirm");
    try testing.expectEqualStrings("Press Enter to confirm", t.text);
}

test "shortcut — label + key preset" {
    const t = Tooltip.shortcut("Save", "Ctrl+S");
    try testing.expectEqualStrings("Save", t.title.?);
    try testing.expectEqualStrings("Ctrl+S", t.text);
}

// ---------------------------------------------------------------------------
// State management
// ---------------------------------------------------------------------------

test "show / hide / toggle" {
    var t = Tooltip.init("Tip");
    try testing.expect(!t.visible);

    t.show();
    try testing.expect(t.visible);
    try testing.expect(t.isVisible());

    t.hide();
    try testing.expect(!t.visible);

    t.toggle();
    try testing.expect(t.visible);
    t.toggle();
    try testing.expect(!t.visible);
}

// ---------------------------------------------------------------------------
// Rendering — renderBox
// ---------------------------------------------------------------------------

test "renderBox produces output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Hello world");
    const box = try t.renderBox(alloc);
    try testing.expect(box.len > 0);
    // Should contain the text
    try testing.expect(std.mem.indexOf(u8, box, "Hello world") != null);
}

test "renderBox with title" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.titled("Title", "Body text");
    const box = try t.renderBox(alloc);
    try testing.expect(std.mem.indexOf(u8, box, "Title") != null);
    try testing.expect(std.mem.indexOf(u8, box, "Body text") != null);
}

test "renderBox multi-line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Line 1\nLine 2");
    t.padding = .{ .top = 0, .right = 1, .bottom = 0, .left = 1 };
    const box = try t.renderBox(alloc);
    try testing.expect(std.mem.indexOf(u8, box, "Line 1") != null);
    try testing.expect(std.mem.indexOf(u8, box, "Line 2") != null);
}

test "renderBox respects max_width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Short");
    t.max_width = 20;
    t.padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 };
    const box = try t.renderBox(alloc);
    const w = zz.measure.maxLineWidth(box);
    // box_w = content_w + 2 (borders) + padding. Short = 5, so 5+2 = 7
    try testing.expect(w <= 22); // max_width + borders
}

// ---------------------------------------------------------------------------
// Rendering — render (full canvas)
// ---------------------------------------------------------------------------

test "render returns empty when not visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Tip");
    const output = try t.render(alloc, 80, 24);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "render produces output when visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Hello");
    t.target_x = 10;
    t.target_y = 5;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "render with different placements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const placements = [_]Tooltip.Placement{ .top, .bottom, .left, .right };
    for (placements) |p| {
        var t = Tooltip.init("Tip");
        t.target_x = 20;
        t.target_y = 12;
        t.placement = p;
        t.show();
        const output = try t.render(alloc, 80, 24);
        try testing.expect(output.len > 0);
    }
}

test "render without arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("No arrow");
    t.show_arrow = false;
    t.target_x = 10;
    t.target_y = 5;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

// ---------------------------------------------------------------------------
// Rendering — overlay
// ---------------------------------------------------------------------------

test "overlay returns base when not visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Tip");
    const base = "Hello world";
    const output = try t.overlay(alloc, base, 80, 24);
    try testing.expectEqualStrings(base, output);
}

test "overlay composites tooltip onto base" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.target_x = 5;
    t.target_y = 1;
    t.show();
    const base = "Line one text here\nLine two text here\nLine three here";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);
}

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

test "tooltip at edge of terminal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Edge test");
    t.target_x = 78;
    t.target_y = 23;
    t.placement = .bottom;
    t.show();
    // Should not crash — position clamped to bounds
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "tooltip at origin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Origin");
    t.target_x = 0;
    t.target_y = 0;
    t.placement = .top;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "tooltip with gap" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Gapped");
    t.target_x = 10;
    t.target_y = 10;
    t.gap = 2;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "empty tooltip text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("");
    t.show();
    const box = try t.renderBox(alloc);
    try testing.expect(box.len > 0); // Still renders box frame
}

// ---------------------------------------------------------------------------
// Arrow customization
// ---------------------------------------------------------------------------

test "custom arrow characters" {
    var t = Tooltip.init("Custom arrows");
    t.arrow_up = "^";
    t.arrow_down = "v";
    t.arrow_left = "<";
    t.arrow_right = ">";
    try testing.expectEqualStrings("^", t.arrow_up);
    try testing.expectEqualStrings("v", t.arrow_down);
}

test "render with custom arrow chars" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Custom");
    t.arrow_up = "^";
    t.target_x = 10;
    t.target_y = 5;
    t.placement = .bottom;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "^") != null);
}

test "render left/right placement shows arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Right placement
    var t = Tooltip.init("Right");
    t.arrow_left = "<";
    t.target_x = 10;
    t.target_y = 12;
    t.target_width = 4;
    t.placement = .right;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(std.mem.indexOf(u8, output, "<") != null);
}

test "overlay left/right placement shows arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Left");
    t.arrow_right = ">";
    t.target_x = 40;
    t.target_y = 5;
    t.target_width = 4;
    t.placement = .left;
    t.show();
    const base = "Some base content that is wide enough for the test overlay to work";
    const output = try t.overlay(alloc, base, 80, 12);
    try testing.expect(std.mem.indexOf(u8, output, ">") != null);
}

test "empty arrow string hides arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("No arrow char");
    t.arrow_up = "";
    t.target_x = 10;
    t.target_y = 5;
    t.placement = .bottom;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}
