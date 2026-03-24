const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Toast init defaults" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try testing.expect(!t.hasMessages());
    try testing.expectEqual(@as(usize, 0), t.count());
    try testing.expect(t.show_icons);
    try testing.expect(t.show_border);
    try testing.expectEqual(zz.ToastPosition.top_right, t.position);
}

test "Toast push and count" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Hello", .info, 3000, 0);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expect(t.hasMessages());

    try t.push("World", .success, 3000, 0);
    try testing.expectEqual(@as(usize, 2), t.count());
}

test "Toast dismiss removes last" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("First", .info, 3000, 0);
    try t.push("Second", .success, 3000, 0);
    try testing.expectEqual(@as(usize, 2), t.count());

    t.dismiss();
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("First", t.messages.items[0].text);
}

test "Toast dismissAll clears everything" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("A", .info, 3000, 0);
    try t.push("B", .warning, 3000, 0);
    try t.push("C", .err, 3000, 0);

    t.dismissAll();
    try testing.expectEqual(@as(usize, 0), t.count());
}

test "Toast update removes expired messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Short", .info, 1000, 0); // 1 second
    try t.push("Long", .success, 5000, 0); // 5 seconds

    // After 2 seconds, short should be gone
    t.update(2_000_000_000);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("Long", t.messages.items[0].text);
}

test "Toast persistent messages survive update" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.pushPersistent("Sticky", .warning, 0);
    try t.push("Timed", .info, 1000, 0);

    // After 2 seconds
    t.update(2_000_000_000);
    try testing.expectEqual(@as(usize, 1), t.count());
    try testing.expectEqualStrings("Sticky", t.messages.items[0].text);
}

test "Toast view renders empty when no messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    const output = try t.view(testing.allocator, 0);
    defer testing.allocator.free(output);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "Toast view renders messages" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    try t.push("Test message", .info, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
}

test "Toast max_visible limits display" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    t.max_visible = 2;

    try t.push("One", .info, 3000, 0);
    try t.push("Two", .info, 3000, 0);
    try t.push("Three", .info, 3000, 0);

    try testing.expectEqual(@as(usize, 3), t.count()); // all stored

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
    // Should contain overflow indicator
    try testing.expect(std.mem.indexOf(u8, output, "+1 more") != null);
}

test "Toast without borders" {
    var t = zz.Toast.init(testing.allocator);
    defer t.deinit();

    t.show_border = false;

    try t.push("No border", .success, 3000, 0);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const output = try t.view(arena.allocator(), 0);
    try testing.expect(output.len > 0);
}
