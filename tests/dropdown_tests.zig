const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

const TestValue = enum { a, b, c, d, e };

test "Dropdown init has correct defaults" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try testing.expect(!dd.expanded);
    try testing.expect(dd.focused);
    try testing.expect(!dd.multi_select);
    try testing.expect(dd.close_on_select);
    try testing.expect(dd.selected_index == null);
    try testing.expectEqual(@as(usize, 0), dd.items.items.len);
}

test "Dropdown addItem increases item count" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = true });

    try testing.expectEqual(@as(usize, 2), dd.items.items.len);
    try testing.expectEqual(@as(usize, 2), dd.filtered_indices.items.len);
}

test "Dropdown open and close" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });

    try testing.expect(!dd.expanded);
    dd.open();
    try testing.expect(dd.expanded);
    dd.close();
    try testing.expect(!dd.expanded);
}

test "Dropdown handleKey opens on Enter when collapsed" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = true });

    dd.handleKey(.{ .key = .enter, .modifiers = .{} });
    try testing.expect(dd.expanded);
}

test "Dropdown selects item on Enter when expanded" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = true });

    dd.open();
    // Move to second item
    dd.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), dd.cursor);

    // Select it
    dd.handleKey(.{ .key = .enter, .modifiers = .{} });
    try testing.expect(!dd.expanded); // closed after select
    try testing.expectEqual(@as(?usize, 1), dd.selected_index);
    try testing.expectEqual(TestValue.b, dd.selectedValue().?);
}

test "Dropdown multi-select toggles with space" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    dd.multi_select = true;
    dd.close_on_select = false;

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .c, .label = "Charlie", .description = "", .enabled = true });

    dd.open();

    // Select first
    dd.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(dd.expanded); // stays open
    try testing.expectEqual(@as(u32, 1), dd.selected_indices.count());

    // Move down and select second
    dd.handleKey(.{ .key = .down, .modifiers = .{} });
    dd.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(u32, 2), dd.selected_indices.count());

    // Toggle first off
    dd.handleKey(.{ .key = .up, .modifiers = .{} });
    dd.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(u32, 1), dd.selected_indices.count());
}

test "Dropdown skips disabled items" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = false });
    try dd.addItem(.{ .value = .c, .label = "Charlie", .description = "", .enabled = true });

    dd.open();

    // Cursor is at 0 (Alpha), move down should skip Beta
    dd.handleKey(.{ .key = .down, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 2), dd.cursor);
}

test "Dropdown Escape closes" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });

    dd.open();
    try testing.expect(dd.expanded);

    dd.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expect(!dd.expanded);
}

test "Dropdown does not select disabled item" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = false });

    dd.open();
    dd.handleKey(.{ .key = .enter, .modifiers = .{} });
    // Should not have selected anything
    try testing.expect(dd.selected_index == null);
}

test "Dropdown view renders without error" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    try dd.addItem(.{ .value = .b, .label = "Beta", .description = "", .enabled = true });

    // Use arena for view rendering (matches real usage where frame allocator is arena)
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Collapsed view
    const collapsed = try dd.view(alloc);
    try testing.expect(collapsed.len > 0);

    // Expanded view
    dd.open();
    const expanded = try dd.view(alloc);
    try testing.expect(expanded.len > collapsed.len);
}

test "Dropdown focus and blur" {
    var dd = zz.Dropdown(TestValue).init(testing.allocator);
    defer dd.deinit();

    try testing.expect(dd.focused);
    dd.blur();
    try testing.expect(!dd.focused);

    // Should not respond to keys when blurred
    try dd.addItem(.{ .value = .a, .label = "Alpha", .description = "", .enabled = true });
    dd.handleKey(.{ .key = .enter, .modifiers = .{} });
    try testing.expect(!dd.expanded);

    dd.focus();
    try testing.expect(dd.focused);
}
