const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const TestAction = enum { new, open, save, quit, undo, redo };
const MB = zz.MenuBar(TestAction);

test "MenuBar init defaults" {
    const mb = MB.init();
    try testing.expectEqual(MB.State.closed, mb.state);
    try testing.expectEqual(@as(usize, 0), mb.menu_count);
    try testing.expect(mb.selected_action == null);
}

test "MenuBar addMenu" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "Ctrl+N", .new),
        MB.action("Open", "", .open),
        MB.separator(),
        MB.action("Quit", "Ctrl+Q", .quit),
    });

    try testing.expectEqual(@as(usize, 1), mb.menu_count);
    try testing.expectEqualStrings("File", mb.menus[0].?.label);
    try testing.expectEqual(@as(usize, 4), mb.menus[0].?.item_count);
}

test "MenuBar activate and deactivate" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{MB.action("New", "", .new)});

    mb.activate();
    try testing.expectEqual(MB.State.bar_focused, mb.state);
    try testing.expect(mb.isOpen());

    mb.deactivate();
    try testing.expectEqual(MB.State.closed, mb.state);
    try testing.expect(!mb.isOpen());
}

test "MenuBar navigate bar with left/right" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{MB.action("New", "", .new)});
    mb.addMenu("Edit", 'E', &.{MB.action("Undo", "", .undo)});
    mb.addMenu("Help", 'H', &.{MB.action("Quit", "", .quit)});

    mb.activate();
    try testing.expectEqual(@as(usize, 0), mb.active_menu);

    _ = mb.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), mb.active_menu);

    _ = mb.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 2), mb.active_menu);

    // Wrap around
    _ = mb.handleKey(.{ .key = .right, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 0), mb.active_menu);
}

test "MenuBar open dropdown with Down" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "", .new),
        MB.action("Open", "", .open),
    });

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(MB.State.dropdown_open, mb.state);
}

test "MenuBar select action with Enter" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "", .new),
        MB.action("Open", "", .open),
    });

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} }); // open dropdown
    try testing.expectEqual(@as(usize, 0), mb.active_item);

    _ = mb.handleKey(.{ .key = .enter, .modifiers = .{} }); // select "New"
    try testing.expectEqual(MB.State.closed, mb.state);

    const act = mb.getSelectedAction();
    try testing.expectEqual(TestAction.new, act.?);
}

test "MenuBar navigate dropdown items" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "", .new),
        MB.action("Open", "", .open),
        MB.action("Save", "", .save),
    });

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} }); // open dropdown
    try testing.expectEqual(@as(usize, 0), mb.active_item);

    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), mb.active_item);

    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 2), mb.active_item);

    // Wrap
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 0), mb.active_item);
}

test "MenuBar skips separators" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "", .new),
        MB.separator(),
        MB.action("Quit", "", .quit),
    });

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} }); // open dropdown
    try testing.expectEqual(@as(usize, 0), mb.active_item);

    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    // Should skip separator (index 1) and land on Quit (index 2)
    try testing.expectEqual(@as(usize, 2), mb.active_item);
}

test "MenuBar skips disabled items" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "", .new),
        MB.disabledAction("Save", "", .save),
        MB.action("Quit", "", .quit),
    });

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} }); // open dropdown
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    // Should skip disabled "Save" and land on "Quit"
    try testing.expectEqual(@as(usize, 2), mb.active_item);
}

test "MenuBar Escape closes dropdown then bar" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{MB.action("New", "", .new)});

    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} }); // open
    try testing.expectEqual(MB.State.dropdown_open, mb.state);

    _ = mb.handleKey(.{ .key = .escape, .modifiers = .{} }); // close dropdown
    try testing.expectEqual(MB.State.bar_focused, mb.state);

    _ = mb.handleKey(.{ .key = .escape, .modifiers = .{} }); // close bar
    try testing.expectEqual(MB.State.closed, mb.state);
}

test "MenuBar view renders" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{
        MB.action("New", "Ctrl+N", .new),
        MB.action("Open", "", .open),
    });

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Closed bar
    const closed = try mb.view(arena.allocator(), 80);
    try testing.expect(closed.len > 0);

    // Open dropdown
    mb.activate();
    _ = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    const opened = try mb.view(arena.allocator(), 80);
    try testing.expect(opened.len > closed.len);
}

test "MenuBar does not respond when closed" {
    var mb = MB.init();
    mb.addMenu("File", 'F', &.{MB.action("New", "", .new)});

    const consumed = mb.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expect(!consumed);
    try testing.expectEqual(MB.State.closed, mb.state);
}
