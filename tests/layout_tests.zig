//! Layout system tests

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "measure.width - simple string" {
    try testing.expectEqual(@as(usize, 5), zz.width("hello"));
    try testing.expectEqual(@as(usize, 0), zz.width(""));
    try testing.expectEqual(@as(usize, 3), zz.width("abc"));
}

test "measure.width - with newlines" {
    try testing.expectEqual(@as(usize, 5), zz.width("hello\nworld"));
    try testing.expectEqual(@as(usize, 5), zz.width("hello\nhi"));
    try testing.expectEqual(@as(usize, 3), zz.width("ab\nabc"));
}

test "measure.width - ANSI sequences excluded" {
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b[31mhello\x1b[0m"));
    try testing.expectEqual(@as(usize, 5), zz.width("\x1b[1;32mhello\x1b[0m"));
}

test "measure.height - simple" {
    try testing.expectEqual(@as(usize, 1), zz.height("hello"));
    try testing.expectEqual(@as(usize, 0), zz.height(""));
    try testing.expectEqual(@as(usize, 2), zz.height("hello\nworld"));
    try testing.expectEqual(@as(usize, 3), zz.height("a\nb\nc"));
}

test "measure.size" {
    const s = zz.layout.measure.size("hello\nworld!");
    try testing.expectEqual(@as(usize, 6), s.width);
    try testing.expectEqual(@as(usize, 2), s.height);
}

test "measure.padRight" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.padRight(allocator, "hi", 5);
    defer allocator.free(result);
    try testing.expectEqualStrings("hi   ", result);
}

test "measure.padLeft" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.padLeft(allocator, "hi", 5);
    defer allocator.free(result);
    try testing.expectEqualStrings("   hi", result);
}

test "measure.center" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.center(allocator, "hi", 6);
    defer allocator.free(result);
    try testing.expectEqualStrings("  hi  ", result);
}

test "measure.truncate" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.truncate(allocator, "hello world", 8);
    defer allocator.free(result);
    try testing.expectEqualStrings("hello...", result);
}

test "measure.truncate - no truncation needed" {
    const allocator = testing.allocator;

    const result = try zz.layout.measure.truncate(allocator, "hi", 10);
    defer allocator.free(result);
    try testing.expectEqualStrings("hi", result);
}

test "join.horizontal - basic" {
    const allocator = testing.allocator;

    const result = try zz.join.horizontal(allocator, .top, &.{ "A", "B", "C" });
    defer allocator.free(result);
    try testing.expectEqualStrings("ABC", result);
}

test "join.horizontal - multiline" {
    const allocator = testing.allocator;

    const result = try zz.join.horizontal(allocator, .top, &.{ "A\nB", "1\n2" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A1\nB2", result);
}

test "join.vertical - basic" {
    const allocator = testing.allocator;

    const result = try zz.join.vertical(allocator, .left, &.{ "A", "B", "C" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A\nB\nC", result);
}

test "join.vertical - different widths" {
    const allocator = testing.allocator;

    const result = try zz.join.vertical(allocator, .left, &.{ "short", "longer text" });
    defer allocator.free(result);
    // First line should be padded
    var iter = std.mem.splitSequence(u8, result, "\n");
    const first = iter.next().?;
    const second = iter.next().?;
    try testing.expectEqual(first.len, second.len);
}

test "place - center" {
    const allocator = testing.allocator;

    const result = try zz.place.place(allocator, 5, 3, .center, .middle, "X");
    defer allocator.free(result);
    try testing.expect(result.len > 0);
}

test "joinHorizontal convenience" {
    const allocator = testing.allocator;

    const result = try zz.joinHorizontal(allocator, &.{ "A", "B" });
    defer allocator.free(result);
    try testing.expectEqualStrings("AB", result);
}

test "joinVertical convenience" {
    const allocator = testing.allocator;

    const result = try zz.joinVertical(allocator, &.{ "A", "B" });
    defer allocator.free(result);
    try testing.expectEqualStrings("A\nB", result);
}
