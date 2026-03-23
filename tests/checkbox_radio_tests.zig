const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

// ── Checkbox tests ──

test "Checkbox init defaults" {
    const cb = zz.Checkbox.init("Test");
    try testing.expect(!cb.checked);
    try testing.expect(cb.enabled);
    try testing.expect(cb.focused);
    try testing.expectEqualStrings("Test", cb.label);
}

test "Checkbox toggle" {
    var cb = zz.Checkbox.init("Test");
    try testing.expect(!cb.checked);
    cb.toggle();
    try testing.expect(cb.checked);
    cb.toggle();
    try testing.expect(!cb.checked);
}

test "Checkbox toggle respects enabled" {
    var cb = zz.Checkbox.init("Test");
    cb.enabled = false;
    cb.toggle();
    try testing.expect(!cb.checked);
}

test "Checkbox handleKey toggles on space" {
    var cb = zz.Checkbox.init("Test");
    cb.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(cb.checked);
}

test "Checkbox ignores keys when not focused" {
    var cb = zz.Checkbox.init("Test");
    cb.blur();
    cb.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(!cb.checked);
}

test "Checkbox view renders" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var cb = zz.Checkbox.init("Accept");
    const unchecked = try cb.view(arena.allocator());
    try testing.expect(unchecked.len > 0);

    cb.checked = true;
    const checked = try cb.view(arena.allocator());
    try testing.expect(checked.len > 0);
}

// ── CheckboxGroup tests ──

const TestVal = enum { a, b, c, d };

test "CheckboxGroup add and toggle" {
    var cg = zz.CheckboxGroup(TestVal).init(testing.allocator);
    defer cg.deinit();

    try cg.addItems(&.{
        .{ .value = .a, .label = "Alpha", .description = "", .enabled = true, .checked = false },
        .{ .value = .b, .label = "Beta", .description = "", .enabled = true, .checked = false },
        .{ .value = .c, .label = "Charlie", .description = "", .enabled = true, .checked = false },
    });

    try testing.expectEqual(@as(usize, 0), cg.checkedCount());

    // Toggle first item
    cg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), cg.checkedCount());
    try testing.expect(cg.items.items[0].checked);

    // Move down and toggle second
    cg.handleKey(.{ .key = .down, .modifiers = .{} });
    cg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 2), cg.checkedCount());
}

test "CheckboxGroup selectAll and selectNone" {
    var cg = zz.CheckboxGroup(TestVal).init(testing.allocator);
    defer cg.deinit();

    try cg.addItems(&.{
        .{ .value = .a, .label = "A", .description = "", .enabled = true, .checked = false },
        .{ .value = .b, .label = "B", .description = "", .enabled = true, .checked = false },
        .{ .value = .c, .label = "C", .description = "", .enabled = false, .checked = false },
    });

    cg.selectAll();
    try testing.expectEqual(@as(usize, 2), cg.checkedCount()); // disabled not selected
    try testing.expect(!cg.items.items[2].checked);

    cg.selectNone();
    try testing.expectEqual(@as(usize, 0), cg.checkedCount());
}

test "CheckboxGroup invertSelection" {
    var cg = zz.CheckboxGroup(TestVal).init(testing.allocator);
    defer cg.deinit();

    try cg.addItems(&.{
        .{ .value = .a, .label = "A", .description = "", .enabled = true, .checked = true },
        .{ .value = .b, .label = "B", .description = "", .enabled = true, .checked = false },
    });

    cg.invertSelection();
    try testing.expect(!cg.items.items[0].checked);
    try testing.expect(cg.items.items[1].checked);
}

test "CheckboxGroup max_selected constraint" {
    var cg = zz.CheckboxGroup(TestVal).init(testing.allocator);
    defer cg.deinit();

    cg.max_selected = 1;

    try cg.addItems(&.{
        .{ .value = .a, .label = "A", .description = "", .enabled = true, .checked = false },
        .{ .value = .b, .label = "B", .description = "", .enabled = true, .checked = false },
    });

    // Select first
    cg.toggleCurrent();
    try testing.expectEqual(@as(usize, 1), cg.checkedCount());

    // Try to select second - should fail
    cg.handleKey(.{ .key = .down, .modifiers = .{} });
    cg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), cg.checkedCount());
    try testing.expect(!cg.items.items[1].checked);
}

// ── RadioGroup tests ──

const Exp = enum { beginner, intermediate, advanced };

test "RadioGroup init defaults" {
    var rg = zz.RadioGroup(Exp).init(testing.allocator);
    defer rg.deinit();

    try testing.expect(rg.selected == null);
    try testing.expect(rg.focused);
}

test "RadioGroup select enforces single selection" {
    var rg = zz.RadioGroup(Exp).init(testing.allocator);
    defer rg.deinit();

    try rg.addOptions(&.{
        .{ .value = .beginner, .label = "Beginner", .description = "", .enabled = true },
        .{ .value = .intermediate, .label = "Intermediate", .description = "", .enabled = true },
        .{ .value = .advanced, .label = "Advanced", .description = "", .enabled = true },
    });

    // Select first
    rg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(?usize, 0), rg.selected);
    try testing.expectEqual(Exp.beginner, rg.selectedValue().?);

    // Move down and select second
    rg.handleKey(.{ .key = .down, .modifiers = .{} });
    rg.handleKey(.{ .key = .enter, .modifiers = .{} });
    try testing.expectEqual(@as(?usize, 1), rg.selected);
    try testing.expectEqual(Exp.intermediate, rg.selectedValue().?);
}

test "RadioGroup does not select disabled" {
    var rg = zz.RadioGroup(Exp).init(testing.allocator);
    defer rg.deinit();

    try rg.addOptions(&.{
        .{ .value = .beginner, .label = "Beginner", .description = "", .enabled = false },
    });

    rg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(rg.selected == null);
}

test "RadioGroup view renders" {
    var rg = zz.RadioGroup(Exp).init(testing.allocator);
    defer rg.deinit();

    try rg.addOptions(&.{
        .{ .value = .beginner, .label = "Beginner", .description = "", .enabled = true },
        .{ .value = .advanced, .label = "Advanced", .description = "", .enabled = true },
    });

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try rg.view(arena.allocator());
    try testing.expect(output.len > 0);
}

test "RadioGroup focus and blur" {
    var rg = zz.RadioGroup(Exp).init(testing.allocator);
    defer rg.deinit();

    try rg.addOptions(&.{
        .{ .value = .beginner, .label = "Beginner", .description = "", .enabled = true },
    });

    rg.blur();
    rg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(rg.selected == null);

    rg.focus();
    rg.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expectEqual(@as(?usize, 0), rg.selected);
}
