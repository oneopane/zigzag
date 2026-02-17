//! Input handling tests

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

fn stripAnsi(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b) {
            i += 1;
            if (i < text.len and text[i] == '[') {
                i += 1;
                while (i < text.len) : (i += 1) {
                    const c = text[i];
                    if (c >= 0x40 and c <= 0x7E) {
                        i += 1;
                        break;
                    }
                }
            }
            continue;
        }

        try out.append(text[i]);
        i += 1;
    }
    return out.toOwnedSlice();
}

test "Key parsing - single character" {
    const result = zz.input.keyboard.parse("a");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .char);
    try testing.expectEqual(@as(u21, 'a'), result.result.key.key.char);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - escape key" {
    const result = zz.input.keyboard.parse("\x1b");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .escape);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - arrow up" {
    const result = zz.input.keyboard.parse("\x1b[A");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .up);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow down" {
    const result = zz.input.keyboard.parse("\x1b[B");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .down);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow right" {
    const result = zz.input.keyboard.parse("\x1b[C");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .right);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow left" {
    const result = zz.input.keyboard.parse("\x1b[D");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .left);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - backspace" {
    const result = zz.input.keyboard.parse("\x7f");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .backspace);
}

test "Key parsing - enter" {
    const result = zz.input.keyboard.parse("\x0d");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .enter);
}

test "Key parsing - function keys" {
    const f1 = zz.input.keyboard.parse("\x1bOP");
    try testing.expect(f1.result == .key);
    try testing.expect(f1.result.key.key == .f1);

    const f2 = zz.input.keyboard.parse("\x1bOQ");
    try testing.expect(f2.result == .key);
    try testing.expect(f2.result.key.key == .f2);
}

test "Key parsing - delete" {
    const result = zz.input.keyboard.parse("\x1b[3~");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .delete);
}

test "Key parsing - home/end" {
    const home = zz.input.keyboard.parse("\x1b[H");
    try testing.expect(home.result == .key);
    try testing.expect(home.result.key.key == .home);

    const end = zz.input.keyboard.parse("\x1b[F");
    try testing.expect(end.result == .key);
    try testing.expect(end.result.key.key == .end);
}

test "Key parsing - page up/down" {
    const pgup = zz.input.keyboard.parse("\x1b[5~");
    try testing.expect(pgup.result == .key);
    try testing.expect(pgup.result.key.key == .page_up);

    const pgdn = zz.input.keyboard.parse("\x1b[6~");
    try testing.expect(pgdn.result == .key);
    try testing.expect(pgdn.result.key.key == .page_down);
}

test "Modifiers struct" {
    const none = zz.Modifiers.none;
    try testing.expect(!none.any());

    const ctrl = zz.Modifiers{ .ctrl = true };
    try testing.expect(ctrl.any());
    try testing.expect(ctrl.ctrl);
    try testing.expect(!ctrl.alt);
}

test "KeyEvent format" {
    const allocator = testing.allocator;

    const event = zz.KeyEvent{
        .key = .{ .char = 'a' },
        .modifiers = .{ .ctrl = true },
    };

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try event.format("", .{}, buf.writer());
    try testing.expectEqualStrings("ctrl+a", buf.items);
}

test "parseAll multiple keys" {
    const allocator = testing.allocator;

    const events = try zz.input.keyboard.parseAll(allocator, "abc");
    defer allocator.free(events);

    try testing.expectEqual(@as(usize, 3), events.len);
    try testing.expect(events[0] == .key);
    try testing.expectEqual(@as(u21, 'a'), events[0].key.key.char);
}

test "TextInput accepts multi-character paste commits (IME-like)" {
    var input = zz.TextInput.init(testing.allocator);
    defer input.deinit();

    input.handleKey(.{ .key = .{ .paste = "中文输入" } });

    try testing.expectEqualStrings("中文输入", input.getValue());
}

test "TextArea accepts multi-character paste commits (IME-like)" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.handleKey(.{ .key = .{ .paste = "中文输入" } });

    const value = try area.getValue(testing.allocator);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("中文输入", value);
}

test "TextArea keeps cursor on UTF-8 boundaries after vertical move" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.setValue("abcd\n中文") catch unreachable;
    area.handleKey(.{ .key = .end });
    area.handleKey(.{ .key = .down });

    const value = try area.getValue(testing.allocator);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("abcd\n中文", value);

    area.handleKey(.{ .key = .{ .char = 'X' } });
    const updated = try area.getValue(testing.allocator);
    defer testing.allocator.free(updated);
    try testing.expectEqualStrings("abcd\n中X文", updated);
}

test "TextArea cursorDisplayColumn uses visual width for CJK" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.handleKey(.{ .key = .{ .paste = "中a" } });
    area.handleKey(.{ .key = .left });

    try testing.expectEqual(@as(usize, 2), area.cursorDisplayColumn());
}

test "TextArea word_wrap wraps long lines in view" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(5, 3);
    try area.setValue("abcdefghij");
    area.blur();

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);

    try testing.expectEqualStrings("abcde\nfghij\n     ", plain);
}

test "TextArea word_wrap moves cursor vertically across wrapped segments" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(4, 3);
    try area.setValue("abcdefgh");

    area.handleKey(.{ .key = .right });
    area.handleKey(.{ .key = .down });

    try testing.expectEqual(@as(usize, 0), area.cursor_row);
    try testing.expectEqual(@as(usize, 5), area.cursor_col);

    area.handleKey(.{ .key = .up });
    try testing.expectEqual(@as(usize, 1), area.cursor_col);
}

test "TextArea word_wrap keeps cursor visible by wrapped row" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.word_wrap = true;
    area.setSize(5, 2);
    try area.setValue("abcdefghijk");

    area.handleKey(.{ .key = .end });
    area.blur();

    try testing.expectEqual(@as(usize, 1), area.viewport_row);

    const rendered = try area.view(testing.allocator);
    defer testing.allocator.free(rendered);
    const plain = try stripAnsi(testing.allocator, rendered);
    defer testing.allocator.free(plain);
    try testing.expectEqualStrings("fghij\nk    ", plain);
}
