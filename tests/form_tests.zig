const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Form init defaults" {
    const form = zz.Form(4).init();
    try testing.expectEqual(@as(usize, 0), form.field_count);
    try testing.expect(!form.submitted);
    try testing.expect(!form.cancelled);
}

test "Form addField increases count" {
    var cb1 = zz.Checkbox.init("Option A");
    var cb2 = zz.Checkbox.init("Option B");

    var form = zz.Form(4).init();
    form.addField("First", &cb1, .{});
    form.addField("Second", &cb2, .{});

    try testing.expectEqual(@as(usize, 2), form.field_count);
}

test "Form focus cycling with Tab" {
    var cb1 = zz.Checkbox.init("A");
    var cb2 = zz.Checkbox.init("B");

    var form = zz.Form(4).init();
    form.addField("First", &cb1, .{});
    form.addField("Second", &cb2, .{});
    form.initFocus();

    try testing.expectEqual(@as(usize, 0), form.focusedIndex());

    // Tab to next
    _ = form.handleKey(.{ .key = .tab, .modifiers = .{} });
    try testing.expectEqual(@as(usize, 1), form.focusedIndex());
}

test "Form forwards keys to active field" {
    var cb = zz.Checkbox.init("Accept");

    var form = zz.Form(4).init();
    form.addField("Terms", &cb, .{});
    form.initFocus();

    // Space should toggle checkbox
    _ = form.handleKey(.{ .key = .space, .modifiers = .{} });
    try testing.expect(cb.checked);
}

test "Form escape cancels" {
    var cb = zz.Checkbox.init("Test");
    var form = zz.Form(4).init();
    form.addField("Field", &cb, .{});

    _ = form.handleKey(.{ .key = .escape, .modifiers = .{} });
    try testing.expect(form.isCancelled());
}

test "Form Ctrl+Enter submits" {
    var cb = zz.Checkbox.init("Test");
    var form = zz.Form(4).init();
    form.addField("Field", &cb, .{});

    _ = form.handleKey(.{ .key = .enter, .modifiers = .{ .ctrl = true } });
    try testing.expect(form.isSubmitted());
}

test "Form reset clears state" {
    var cb = zz.Checkbox.init("Test");
    var form = zz.Form(4).init();
    form.addField("Field", &cb, .{});

    _ = form.handleKey(.{ .key = .enter, .modifiers = .{ .ctrl = true } });
    try testing.expect(form.isSubmitted());

    form.reset();
    try testing.expect(!form.isSubmitted());
    try testing.expect(!form.isCancelled());
}

test "Form view renders" {
    var cb = zz.Checkbox.init("Accept terms");

    var form = zz.Form(4).init();
    form.title = "Test Form";
    form.addField("Agreement", &cb, .{ .required = true });
    form.initFocus();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try form.view(arena.allocator());
    try testing.expect(output.len > 0);
}
