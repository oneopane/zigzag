//! Keyboard input parsing for terminal applications.
//! Parses ANSI escape sequences into structured key events.

const std = @import("std");
const keys = @import("keys.zig");
const mouse = @import("mouse.zig");

pub const Key = keys.Key;
pub const KeyEvent = keys.KeyEvent;
pub const Modifiers = keys.Modifiers;
pub const MouseEvent = mouse.MouseEvent;

/// Result of parsing input data
pub const ParseResult = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    none,
};

/// Return type for parse functions
pub const ParseReturn = struct { result: ParseResult, consumed: usize };

/// Parse a single input event from raw terminal data
pub fn parse(data: []const u8) ParseReturn {
    if (data.len == 0) return .{ .result = .none, .consumed = 0 };

    // Check for escape sequence
    if (data[0] == 0x1b) {
        if (data.len == 1) {
            // Just escape key
            return .{ .result = .{ .key = .{ .key = .escape } }, .consumed = 1 };
        }

        // CSI sequence
        if (data.len >= 2 and data[1] == '[') {
            if (parseCsi(data)) |result| {
                return result;
            }
        }

        // SS3 sequence (F1-F4 on some terminals)
        if (data.len >= 2 and data[1] == 'O') {
            if (parseSs3(data)) |result| {
                return result;
            }
        }

        // Alt + key
        if (data.len >= 2 and data[1] != '[' and data[1] != 'O') {
            const inner = parse(data[1..]);
            if (inner.result == .key) {
                var key_event = inner.result.key;
                key_event.modifiers.alt = true;
                return .{ .result = .{ .key = key_event }, .consumed = 1 + inner.consumed };
            }
        }

        return .{ .result = .{ .key = .{ .key = .escape } }, .consumed = 1 };
    }

    // Control characters
    if (data[0] < 32) {
        const key_event = parseControl(data[0]);
        return .{ .result = .{ .key = key_event }, .consumed = 1 };
    }

    // DEL character
    if (data[0] == 127) {
        return .{ .result = .{ .key = .{ .key = .backspace } }, .consumed = 1 };
    }

    // UTF-8 character
    const len = std.unicode.utf8ByteSequenceLength(data[0]) catch 1;
    if (len <= data.len) {
        const codepoint = std.unicode.utf8Decode(data[0..len]) catch data[0];
        return .{ .result = .{ .key = .{ .key = .{ .char = codepoint } } }, .consumed = len };
    }

    return .{ .result = .{ .key = .{ .key = .{ .char = data[0] } } }, .consumed = 1 };
}

fn parseControl(c: u8) KeyEvent {
    return switch (c) {
        0 => .{ .key = .null_key, .modifiers = .{ .ctrl = true } },
        9 => .{ .key = .tab },
        10, 13 => .{ .key = .enter },
        27 => .{ .key = .escape },
        1...8, 11, 12, 14...26 => .{
            .key = .{ .char = 'a' + c - 1 },
            .modifiers = .{ .ctrl = true },
        },
        else => .{ .key = .{ .char = c } },
    };
}

fn parseCsi(data: []const u8) ?ParseReturn {
    if (data.len < 3) return null;
    if (data[0] != 0x1b or data[1] != '[') return null;

    // Check for mouse SGR sequence
    if (data.len >= 3 and data[2] == '<') {
        if (mouse.parseSgr(data)) |m| {
            return .{ .result = .{ .mouse = m.event }, .consumed = m.consumed };
        }
    }

    var idx: usize = 2;
    var params: [8]u16 = .{0} ** 8;
    var param_count: usize = 0;

    // Parse parameters
    while (idx < data.len and param_count < params.len) {
        const c = data[idx];
        if (c >= '0' and c <= '9') {
            params[param_count] = params[param_count] * 10 + @as(u16, @intCast(c - '0'));
            idx += 1;
        } else if (c == ';') {
            param_count += 1;
            idx += 1;
        } else {
            break;
        }
    }
    param_count += 1;

    if (idx >= data.len) return null;

    const final_byte = data[idx];
    idx += 1;

    // Determine modifiers from parameter
    var modifiers = Modifiers{};
    if (param_count >= 2 and params[1] > 1) {
        const mod_param = params[1] - 1;
        modifiers.shift = (mod_param & 1) != 0;
        modifiers.alt = (mod_param & 2) != 0;
        modifiers.ctrl = (mod_param & 4) != 0;
    }

    const key: Key = switch (final_byte) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'Z' => {
            modifiers.shift = true;
            return .{ .result = .{ .key = .{ .key = .tab, .modifiers = modifiers } }, .consumed = idx };
        },
        '~' => switch (params[0]) {
            1 => .home,
            2 => .insert,
            3 => .delete,
            4 => .end,
            5 => .page_up,
            6 => .page_down,
            7 => .home,
            8 => .end,
            11 => .f1,
            12 => .f2,
            13 => .f3,
            14 => .f4,
            15 => .f5,
            17 => .f6,
            18 => .f7,
            19 => .f8,
            20 => .f9,
            21 => .f10,
            23 => .f11,
            24 => .f12,
            else => return null,
        },
        else => return null,
    };

    return .{ .result = .{ .key = .{ .key = key, .modifiers = modifiers } }, .consumed = idx };
}

fn parseSs3(data: []const u8) ?ParseReturn {
    if (data.len < 3) return null;
    if (data[0] != 0x1b or data[1] != 'O') return null;

    const key: Key = switch (data[2]) {
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        else => return null,
    };

    return .{ .result = .{ .key = .{ .key = key } }, .consumed = 3 };
}

/// Parse all available input events from a buffer
pub fn parseAll(allocator: std.mem.Allocator, data: []const u8) ![]ParseResult {
    var results = std.array_list.Managed(ParseResult).init(allocator);
    errdefer results.deinit();

    var offset: usize = 0;
    while (offset < data.len) {
        const parsed = parse(data[offset..]);
        if (parsed.consumed == 0) break;

        if (parsed.result != .none) {
            try results.append(parsed.result);
        }
        offset += parsed.consumed;
    }

    return results.toOwnedSlice();
}
