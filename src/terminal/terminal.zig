//! Terminal abstraction layer providing cross-platform terminal control.
//! Handles raw mode, alternate screen, mouse tracking, and input/output.

const std = @import("std");
const builtin = @import("builtin");
pub const ansi = @import("ansi.zig");
pub const screen = @import("screen.zig");
const unicode = @import("../unicode.zig");

// Platform-specific implementation
const platform = if (builtin.os.tag == .windows)
    @import("platform/windows.zig")
else
    @import("platform/posix.zig");

pub const Size = platform.Size;
pub const TerminalError = platform.TerminalError;

pub const UnicodeWidthCapabilities = struct {
    mode_2027: bool = false,
    kitty_text_sizing: bool = false,
    strategy: unicode.WidthStrategy = .legacy_wcwidth,
};

pub const ImageCapabilities = struct {
    kitty_graphics: bool = false,
    iterm2_inline_image: bool = false,
    sixel: bool = false,
};

const Iterm2Capabilities = struct {
    inline_image: bool = false,
    sixel: bool = false,
};

pub const KittyImageFormat = enum(u16) {
    rgb = 24,
    rgba = 32,
    png = 100,
};

pub const KittyImageOptions = struct {
    format: KittyImageFormat = .png,
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

pub const KittyImageFileOptions = struct {
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

pub const Iterm2ImageFileOptions = struct {
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    preserve_aspect_ratio: bool = true,
    move_cursor: bool = true,
};

pub const ImageFileOptions = struct {
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    preserve_aspect_ratio: bool = true,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

pub const SixelImageFileOptions = struct {
    /// Optional max captured converter output (bytes).
    max_output_bytes: usize = 32 * 1024 * 1024,
};

/// Terminal configuration options
pub const Config = struct {
    /// Use alternate screen buffer
    alt_screen: bool = true,
    /// Hide cursor during operation
    hide_cursor: bool = true,
    /// Enable mouse tracking
    mouse: bool = false,
    /// Enable bracketed paste mode
    bracketed_paste: bool = true,
    /// Custom input file (default: stdin)
    input: ?std.fs.File = null,
    /// Custom output file (default: stdout)
    output: ?std.fs.File = null,
    /// Enable Kitty keyboard protocol
    kitty_keyboard: bool = false,
};

/// Terminal abstraction
pub const Terminal = struct {
    state: platform.State,
    config: Config,
    stdout: std.fs.File,
    stdin: std.fs.File,
    write_buffer: [4096]u8 = undefined,
    write_pos: usize = 0,
    unicode_width_caps: UnicodeWidthCapabilities = .{},
    image_caps: ImageCapabilities = .{},

    pub fn init(config: Config) !Terminal {
        const stdout = config.output orelse std.fs.File.stdout();
        const stdin = config.input orelse std.fs.File.stdin();

        var state = platform.State.init();
        // Apply custom fd overrides
        if (builtin.os.tag != .windows) {
            if (config.input) |inp| state.stdin_fd = inp.handle;
            if (config.output) |out| state.stdout_fd = out.handle;
        } else {
            if (config.input) |inp| state.stdin_handle = inp.handle;
            if (config.output) |out| state.stdout_handle = out.handle;
        }

        var term = Terminal{
            .state = state,
            .config = config,
            .stdout = stdout,
            .stdin = stdin,
        };

        try term.setup();
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        self.cleanup();
    }

    pub fn setup(self: *Terminal) !void {
        // Setup signal handlers
        platform.setupSignals() catch {};

        // Enable raw mode
        try platform.enableRawMode(&self.state);

        // Enter alternate screen
        if (self.config.alt_screen) {
            try self.writeBytes(ansi.alt_screen_enter);
            self.state.in_alt_screen = true;
        }

        // Hide cursor
        if (self.config.hide_cursor) {
            try self.writeBytes(ansi.cursor_hide);
        }

        // Enable mouse
        if (self.config.mouse) {
            try self.writeBytes("\x1b[?1003h\x1b[?1006h");
            self.state.mouse_enabled = true;
        }

        // Enable bracketed paste
        if (self.config.bracketed_paste) {
            try self.writeBytes(ansi.bracketed_paste_enable);
        }

        // Enable Kitty keyboard protocol
        if (self.config.kitty_keyboard) {
            try self.writeBytes(ansi.kitty_keyboard_enable);
        }

        self.detectUnicodeWidthCapabilities();
        self.detectImageCapabilities();

        // Clear screen
        try self.writeBytes(ansi.screen_clear);
        try self.writeBytes(ansi.cursor_home);

        try self.flush();
    }

    pub fn cleanup(self: *Terminal) void {
        // Disable Kitty keyboard protocol
        if (self.config.kitty_keyboard) {
            self.writeBytes(ansi.kitty_keyboard_disable) catch {};
        }

        if (self.unicode_width_caps.mode_2027) {
            self.writeBytes(ansi.unicode_width_mode_disable) catch {};
            self.unicode_width_caps.mode_2027 = false;
        }

        // Disable bracketed paste
        if (self.config.bracketed_paste) {
            self.writeBytes(ansi.bracketed_paste_disable) catch {};
        }

        // Disable mouse
        if (self.state.mouse_enabled) {
            self.writeBytes("\x1b[?1006l\x1b[?1003l") catch {};
            self.state.mouse_enabled = false;
        }

        // Show cursor
        if (self.config.hide_cursor) {
            self.writeBytes(ansi.cursor_show) catch {};
        }

        // Exit alternate screen
        if (self.state.in_alt_screen) {
            self.writeBytes(ansi.alt_screen_exit) catch {};
            self.state.in_alt_screen = false;
        }

        // Reset attributes
        self.writeBytes(ansi.reset) catch {};

        self.flush() catch {};

        // Restore terminal mode — always runs even if writes above failed
        platform.disableRawMode(&self.state);
    }

    /// Write bytes to internal buffer
    fn writeBytes(self: *Terminal, bytes: []const u8) !void {
        for (bytes) |byte| {
            if (self.write_pos >= self.write_buffer.len) {
                try self.flush();
            }
            self.write_buffer[self.write_pos] = byte;
            self.write_pos += 1;
        }
    }

    /// Get terminal size
    pub fn getSize(self: *Terminal) !Size {
        return platform.getSize(if (builtin.os.tag == .windows)
            self.state.stdout_handle
        else
            self.state.stdout_fd);
    }

    /// Read input with timeout (in milliseconds)
    pub fn readInput(self: *Terminal, buffer: []u8, timeout_ms: i32) !usize {
        return platform.readInput(&self.state, buffer, timeout_ms);
    }

    /// Check if terminal was resized
    pub fn checkResize(self: *Terminal) bool {
        _ = self;
        return platform.checkResize();
    }

    /// Get a simple writer interface
    pub fn writer(self: *Terminal) Writer {
        return Writer{ .terminal = self };
    }

    /// Flush output buffer
    pub fn flush(self: *Terminal) !void {
        if (self.write_pos > 0) {
            self.stdout.writeAll(self.write_buffer[0..self.write_pos]) catch |err| {
                return switch (err) {
                    error.WouldBlock => error.WouldBlock,
                    else => error.BrokenPipe,
                };
            };
            self.write_pos = 0;
        }
    }

    /// Clear the screen
    pub fn clear(self: *Terminal) !void {
        try self.writeBytes(ansi.screen_clear);
        try self.writeBytes(ansi.cursor_home);
    }

    /// Move cursor to position (0-indexed)
    pub fn moveTo(self: *Terminal, row: u16, col: u16) !void {
        var buf: [32]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row + 1, col + 1 }) catch return;
        try self.writeBytes(len);
    }

    /// Show the cursor
    pub fn showCursor(self: *Terminal) !void {
        try self.writeBytes(ansi.cursor_show);
    }

    /// Hide the cursor
    pub fn hideCursor(self: *Terminal) !void {
        try self.writeBytes(ansi.cursor_hide);
    }

    /// Enable mouse tracking
    pub fn enableMouse(self: *Terminal) !void {
        try self.writeBytes("\x1b[?1003h\x1b[?1006h");
        self.state.mouse_enabled = true;
    }

    /// Disable mouse tracking
    pub fn disableMouse(self: *Terminal) !void {
        try self.writeBytes("\x1b[?1006l\x1b[?1003l");
        self.state.mouse_enabled = false;
    }

    /// Set window title
    pub fn setTitle(self: *Terminal, title: []const u8) !void {
        try self.writeBytes("\x1b]0;");
        try self.writeBytes(title);
        try self.writeBytes("\x07");
    }

    /// Write a string at position
    pub fn writeAt(self: *Terminal, row: u16, col: u16, str: []const u8) !void {
        try self.moveTo(row, col);
        try self.writeBytes(str);
    }

    /// Check if stdin is a TTY
    pub fn isTty(self: *Terminal) bool {
        _ = self;
        return platform.isTty(if (builtin.os.tag == .windows)
            platform.State.init().stdin_handle
        else
            std.posix.STDIN_FILENO);
    }

    pub fn getUnicodeWidthCapabilities(self: *const Terminal) UnicodeWidthCapabilities {
        return self.unicode_width_caps;
    }

    pub fn getImageCapabilities(self: *const Terminal) ImageCapabilities {
        return self.image_caps;
    }

    pub fn supportsKittyGraphics(self: *const Terminal) bool {
        return self.image_caps.kitty_graphics;
    }

    pub fn supportsIterm2InlineImages(self: *const Terminal) bool {
        return self.image_caps.iterm2_inline_image;
    }

    pub fn supportsImages(self: *const Terminal) bool {
        return self.supportsKittyGraphics() or self.supportsIterm2InlineImages() or self.supportsSixel();
    }

    pub fn supportsSixel(self: *const Terminal) bool {
        return self.image_caps.sixel;
    }

    /// Draw image bytes using Kitty graphics protocol (`t=d`).
    /// Returns `false` when unsupported or no data is provided.
    pub fn drawKittyImage(self: *Terminal, image_data: []const u8, options: KittyImageOptions) !bool {
        if (!self.image_caps.kitty_graphics or image_data.len == 0) return false;

        var params_buf: [160]u8 = undefined;
        var stream = std.io.fixedBufferStream(&params_buf);
        const params_writer = stream.writer();

        try params_writer.print("a=T,t=d,f={d}", .{@intFromEnum(options.format)});
        if (options.quiet) try params_writer.writeAll(",q=2");
        if (options.width_cells) |cols| try params_writer.print(",c={d}", .{cols});
        if (options.height_cells) |rows| try params_writer.print(",r={d}", .{rows});
        if (options.image_id) |id| try params_writer.print(",i={d}", .{id});
        if (options.placement_id) |id| try params_writer.print(",p={d}", .{id});
        if (!options.move_cursor) try params_writer.writeAll(",C=1");

        try self.sendKittyGraphicsPayload(stream.getWritten(), image_data);
        return true;
    }

    /// Draw a PNG image by file path using Kitty graphics protocol (`t=f`).
    /// Returns `false` when unsupported or path is empty.
    pub fn drawKittyImageFromFile(self: *Terminal, path: []const u8, options: KittyImageFileOptions) !bool {
        if (!self.image_caps.kitty_graphics or path.len == 0) return false;

        var params_buf: [160]u8 = undefined;
        var stream = std.io.fixedBufferStream(&params_buf);
        const params_writer = stream.writer();

        try params_writer.writeAll("a=T,t=f,f=100");
        if (options.quiet) try params_writer.writeAll(",q=2");
        if (options.width_cells) |cols| try params_writer.print(",c={d}", .{cols});
        if (options.height_cells) |rows| try params_writer.print(",r={d}", .{rows});
        if (options.image_id) |id| try params_writer.print(",i={d}", .{id});
        if (options.placement_id) |id| try params_writer.print(",p={d}", .{id});
        if (!options.move_cursor) try params_writer.writeAll(",C=1");

        try self.sendKittyGraphicsPayload(stream.getWritten(), path);
        return true;
    }

    /// Draw a file image via iTerm2 inline image protocol (`OSC 1337`).
    /// Returns `false` when unsupported or path is empty.
    pub fn drawIterm2ImageFromFile(self: *Terminal, path: []const u8, options: Iterm2ImageFileOptions) !bool {
        if (!self.image_caps.iterm2_inline_image or path.len == 0) return false;

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();

        var params_buf: [192]u8 = undefined;
        var stream = std.io.fixedBufferStream(&params_buf);
        const params_writer = stream.writer();

        try params_writer.writeAll("inline=1");
        if (options.width_cells) |cols| try params_writer.print(";width={d}", .{cols});
        if (options.height_cells) |rows| try params_writer.print(";height={d}", .{rows});
        try params_writer.print(";preserveAspectRatio={d}", .{if (options.preserve_aspect_ratio) @as(u8, 1) else @as(u8, 0)});
        if (!options.move_cursor) try params_writer.writeAll(";doNotMoveCursor=1");
        try params_writer.print(";size={d}", .{stat.size});
        const file_name = std.fs.path.basename(path);
        const file_name_b64_len = std.base64.standard.Encoder.calcSize(file_name.len);
        if (file_name_b64_len <= 512) {
            var file_name_b64_buf: [512]u8 = undefined;
            const file_name_b64 = std.base64.standard.Encoder.encode(file_name_b64_buf[0..file_name_b64_len], file_name);
            try params_writer.print(";name={s}", .{file_name_b64});
        }

        try self.sendIterm2InlineImagePayload(stream.getWritten(), &file, stat.size);
        return true;
    }

    /// Draw an image file using the best available protocol.
    /// Prefers Kitty graphics, then iTerm2 inline images.
    pub fn drawImageFromFile(self: *Terminal, path: []const u8, options: ImageFileOptions) !bool {
        if (self.image_caps.kitty_graphics) {
            return self.drawKittyImageFromFile(path, .{
                .width_cells = options.width_cells,
                .height_cells = options.height_cells,
                .image_id = options.image_id,
                .placement_id = options.placement_id,
                .move_cursor = options.move_cursor,
                .quiet = options.quiet,
            });
        }
        if (self.image_caps.iterm2_inline_image) {
            return self.drawIterm2ImageFromFile(path, .{
                .width_cells = options.width_cells,
                .height_cells = options.height_cells,
                .preserve_aspect_ratio = options.preserve_aspect_ratio,
                .move_cursor = options.move_cursor,
            });
        }
        if (self.image_caps.sixel) {
            return self.drawSixelFromFile(path, .{});
        }
        return false;
    }

    /// Draw a Sixel image from file.
    /// Supports either:
    /// - pre-encoded `.sixel`/`.six` data files, or
    /// - regular image files converted through `img2sixel` when available.
    pub fn drawSixelFromFile(self: *Terminal, path: []const u8, options: SixelImageFileOptions) !bool {
        if (!self.image_caps.sixel or path.len == 0) return false;

        if (isSixelDataPath(path)) {
            var file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            try self.sendSixelPayloadFromFile(&file);
            return true;
        }

        if (!commandExists("img2sixel")) return false;

        const argv = [_][]const u8{ "img2sixel", path };
        const result = try std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &argv,
            .max_output_bytes = options.max_output_bytes,
        });
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| if (code != 0) return error.BrokenPipe,
            else => return error.BrokenPipe,
        }

        try self.sendSixelPayload(result.stdout);
        return true;
    }

    fn detectUnicodeWidthCapabilities(self: *Terminal) void {
        self.unicode_width_caps = .{
            .kitty_text_sizing = self.queryKittyTextSizingSupport() catch false,
        };

        if (!self.isTty()) {
            return;
        }

        if (builtin.os.tag != .windows) {
            self.unicode_width_caps.mode_2027 = self.queryMode2027Support() catch false;
            if (self.unicode_width_caps.mode_2027) {
                self.writeBytes(ansi.unicode_width_mode_enable) catch {};
            }
        }

        self.unicode_width_caps.strategy = self.selectWidthStrategy();
    }

    fn detectImageCapabilities(self: *Terminal) void {
        if (!self.isTty()) {
            self.image_caps = .{};
            return;
        }

        const term_features_owned = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_FEATURES") catch null;
        defer if (term_features_owned) |value| std.heap.page_allocator.free(value);
        const term_features = if (term_features_owned) |value| value else "";

        const kitty_candidate = looksLikeKittyTerminal() or
            envVarEquals("TERM_PROGRAM", "WezTerm") or
            envVarContains("TERM", "wezterm") or
            envVarContains("TERM", "ghostty");
        const iterm_candidate = looksLikeIterm2Terminal() or
            envVarEquals("TERM_PROGRAM", "WezTerm");
        const in_multiplexer = isInsideMultiplexer();

        var kitty = false;
        var iterm = iterm_candidate or termFeaturesContain(term_features, "F");
        var sixel = looksLikeSixelTerminal() or termFeaturesContain(term_features, "Sx");

        if (kitty_candidate) {
            kitty = self.queryKittyGraphicsSupport() catch false;
            // Keep an env fallback only outside multiplexers where probe failures are uncommon.
            if (!kitty and !in_multiplexer) {
                kitty = envVarExists("KITTY_WINDOW_ID");
            }
        }

        if (iterm_candidate or term_features.len > 0) {
            if (self.queryIterm2Capabilities() catch null) |caps| {
                iterm = iterm or caps.inline_image;
                sixel = sixel or caps.sixel;
            }
        }

        if (!sixel) sixel = self.queryPrimaryDeviceAttributesHasParam(4) catch false;

        self.image_caps = .{
            .kitty_graphics = kitty,
            .iterm2_inline_image = iterm,
            .sixel = sixel,
        };
    }

    fn sendKittyGraphicsPayload(self: *Terminal, first_params: []const u8, payload: []const u8) !void {
        const encoder = std.base64.standard.Encoder;
        var b64_buf: [4096]u8 = undefined;
        const raw_chunk_max: usize = (b64_buf.len / 4) * 3;

        var src_index: usize = 0;
        var first = true;

        while (true) {
            const remaining = payload.len - src_index;
            const take = @min(remaining, raw_chunk_max);
            const chunk = payload[src_index .. src_index + take];

            const encoded_len = encoder.calcSize(chunk.len);
            const encoded = encoder.encode(b64_buf[0..encoded_len], chunk);
            const has_more = src_index + take < payload.len;

            if (first) {
                var first_chunk_params: [192]u8 = undefined;
                const params = try std.fmt.bufPrint(
                    &first_chunk_params,
                    "{s},m={d}",
                    .{ first_params, if (has_more) @as(u8, 1) else @as(u8, 0) },
                );
                try ansi.kittyGraphics(self.writer(), params, encoded);
                first = false;
            } else {
                const params = if (has_more) "m=1" else "m=0";
                try ansi.kittyGraphics(self.writer(), params, encoded);
            }

            if (!has_more) break;
            src_index += take;
        }
    }

    fn sendIterm2InlineImagePayload(self: *Terminal, params: []const u8, file: *std.fs.File, file_size: u64) !void {
        const encoder = std.base64.standard.Encoder;
        var raw_buf: [3072]u8 = undefined;
        var b64_buf: [4096]u8 = undefined;
        const encoded_total = std.math.cast(usize, encoder.calcSize(@intCast(file_size))) orelse std.math.maxInt(usize);
        const single_sequence_soft_limit: usize = 750 * 1024;

        if (encoded_total <= single_sequence_soft_limit) {
            try self.writeBytes(ansi.OSC ++ "1337;File=");
            try self.writeBytes(params);
            try self.writeBytes(":");

            while (true) {
                const n = try file.read(&raw_buf);
                if (n == 0) break;
                const encoded_len = encoder.calcSize(n);
                const encoded = encoder.encode(b64_buf[0..encoded_len], raw_buf[0..n]);
                try self.writeBytes(encoded);
            }
            try self.writeBytes("\x07");
            return;
        }

        // iTerm2 supports multipart transfer to avoid oversized OSC sequences.
        try self.writeBytes(ansi.OSC ++ "1337;MultipartFile=");
        try self.writeBytes(params);
        try self.writeBytes("\x07");

        while (true) {
            const n = try file.read(&raw_buf);
            if (n == 0) break;
            const encoded_len = encoder.calcSize(n);
            const encoded = encoder.encode(b64_buf[0..encoded_len], raw_buf[0..n]);
            try self.writeBytes(ansi.OSC ++ "1337;FilePart=");
            try self.writeBytes(encoded);
            try self.writeBytes("\x07");
        }

        try self.writeBytes(ansi.OSC ++ "1337;FileEnd\x07");
    }

    fn sendSixelPayloadFromFile(self: *Terminal, file: *std.fs.File) !void {
        var payload_buf: [4096]u8 = undefined;
        var first_read = true;
        var wrapped = false;

        while (true) {
            const n = try file.read(&payload_buf);
            if (n == 0) break;
            const chunk = payload_buf[0..n];

            if (first_read) {
                first_read = false;
                if (isLikelyFullSixelSequence(chunk)) {
                    wrapped = true;
                } else {
                    try self.writeBytes(ansi.DCS ++ "q");
                }
            }
            try self.writeBytes(chunk);
        }

        if (!first_read and !wrapped) {
            try self.writeBytes(ansi.ST);
        }
    }

    fn sendSixelPayload(self: *Terminal, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        if (isLikelyFullSixelSequence(bytes)) {
            try self.writeBytes(bytes);
            return;
        }
        try self.writeBytes(ansi.DCS ++ "q");
        try self.writeBytes(bytes);
        try self.writeBytes(ansi.ST);
    }

    fn queryKittyGraphicsSupport(self: *Terminal) !bool {
        const probe_id: u32 = 9931;
        self.drainInput();
        try ansi.kittyGraphics(self.writer(), "a=q,i=9931,s=1,v=1,t=d,f=24", "AAAA");
        try self.flush();

        var collected: [1024]u8 = undefined;
        var collected_len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 180;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 30) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, collected.len - collected_len);
            if (copy_len > 0) {
                @memcpy(collected[collected_len .. collected_len + copy_len], chunk[0..copy_len]);
                collected_len += copy_len;
            }

            if (parseKittyGraphicsProbeResponse(collected[0..collected_len], probe_id)) |supported| {
                return supported;
            }
        }

        return false;
    }

    fn parseKittyGraphicsProbeResponse(bytes: []const u8, probe_id: u32) ?bool {
        const prefix = "\x1b_G";
        var search_from: usize = 0;

        var id_buf: [24]u8 = undefined;
        const expected_id = std.fmt.bufPrint(&id_buf, "i={d}", .{probe_id}) catch return null;

        while (search_from < bytes.len) {
            const start = std.mem.indexOfPos(u8, bytes, search_from, prefix) orelse return null;
            const content_start = start + prefix.len;
            const semicolon = std.mem.indexOfScalarPos(u8, bytes, content_start, ';') orelse return null;
            const st_index = indexOfSt(bytes, semicolon + 1) orelse return null;

            const params = bytes[content_start..semicolon];
            const payload = bytes[semicolon + 1 .. st_index];

            if (std.mem.indexOf(u8, params, expected_id) != null) {
                return std.mem.startsWith(u8, payload, "OK");
            }

            search_from = st_index + 2;
        }

        return null;
    }

    fn queryIterm2Capabilities(self: *Terminal) !?Iterm2Capabilities {
        self.drainInput();
        try self.writeBytes(ansi.OSC ++ "1337;Capabilities\x07");
        try self.flush();

        var collected: [2048]u8 = undefined;
        var collected_len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 180;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 30) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, collected.len - collected_len);
            if (copy_len > 0) {
                @memcpy(collected[collected_len .. collected_len + copy_len], chunk[0..copy_len]);
                collected_len += copy_len;
            }

            if (parseIterm2CapabilitiesResponse(collected[0..collected_len])) |caps| {
                return caps;
            }
        }

        return null;
    }

    fn parseIterm2CapabilitiesResponse(bytes: []const u8) ?Iterm2Capabilities {
        const prefix = "\x1b]1337;Capabilities=";
        const start = std.mem.indexOf(u8, bytes, prefix) orelse return null;
        const payload_start = start + prefix.len;
        const end = indexOfOscTerminator(bytes, payload_start) orelse return null;
        const payload = bytes[payload_start..end];
        return .{
            .inline_image = termFeaturesContain(payload, "F"),
            .sixel = termFeaturesContain(payload, "Sx"),
        };
    }

    fn queryPrimaryDeviceAttributesHasParam(self: *Terminal, needle: u16) !bool {
        self.drainInput();
        try self.writeBytes(ansi.CSI ++ "c");
        try self.flush();

        var collected: [1024]u8 = undefined;
        var collected_len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 120;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 25) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, collected.len - collected_len);
            if (copy_len > 0) {
                @memcpy(collected[collected_len .. collected_len + copy_len], chunk[0..copy_len]);
                collected_len += copy_len;
            }

            if (parsePrimaryDeviceAttributes(collected[0..collected_len])) |params| {
                return primaryDeviceAttributesHasParam(params, needle);
            }
        }

        return false;
    }

    fn parsePrimaryDeviceAttributes(bytes: []const u8) ?[]const u8 {
        const prefix = "\x1b[";
        var search_from: usize = 0;

        while (search_from < bytes.len) {
            const start = std.mem.indexOfPos(u8, bytes, search_from, prefix) orelse return null;
            var i = start + prefix.len;

            if (i < bytes.len and bytes[i] == '?') i += 1;
            const params_start = i;

            while (i < bytes.len and ((bytes[i] >= '0' and bytes[i] <= '9') or bytes[i] == ';')) : (i += 1) {}
            if (i >= bytes.len) return null;

            if (bytes[i] == 'c' and i > params_start) {
                return bytes[params_start..i];
            }

            search_from = start + 1;
        }

        return null;
    }

    fn primaryDeviceAttributesHasParam(params: []const u8, needle: u16) bool {
        var it = std.mem.splitScalar(u8, params, ';');
        while (it.next()) |part| {
            if (part.len == 0) continue;
            const value = std.fmt.parseInt(u16, part, 10) catch continue;
            if (value == needle) return true;
        }
        return false;
    }

    fn queryMode2027Support(self: *Terminal) !bool {
        try self.writeBytes(ansi.unicode_width_mode_query);
        try self.flush();

        var collected: [512]u8 = undefined;
        var collected_len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 250;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 40) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, collected.len - collected_len);
            if (copy_len > 0) {
                @memcpy(collected[collected_len .. collected_len + copy_len], chunk[0..copy_len]);
                collected_len += copy_len;
            }

            if (parseMode2027Response(collected[0..collected_len])) |supported| {
                return supported;
            }
        }

        return false;
    }

    fn parseMode2027Response(bytes: []const u8) ?bool {
        const prefix = "\x1b[?2027;";
        var search_from: usize = 0;

        while (search_from < bytes.len) {
            const start = std.mem.indexOfPos(u8, bytes, search_from, prefix) orelse return null;
            var i = start + prefix.len;
            var param: usize = 0;
            var saw_digit = false;

            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {
                saw_digit = true;
                param = param * 10 + (bytes[i] - '0');
            }

            if (!saw_digit) {
                search_from = start + 1;
                continue;
            }

            if (i + 1 < bytes.len and bytes[i] == '$' and bytes[i + 1] == 'y') {
                return param != 0;
            }

            search_from = start + 1;
        }

        return null;
    }

    fn selectWidthStrategy(self: *const Terminal) unicode.WidthStrategy {
        if (isInsideMultiplexer()) {
            return .legacy_wcwidth;
        }

        if (self.unicode_width_caps.mode_2027) {
            return .unicode;
        }

        if (self.unicode_width_caps.kitty_text_sizing) {
            return .unicode;
        }

        if (isKnownUnicodeWidthTerminal()) {
            return .unicode;
        }

        return .legacy_wcwidth;
    }

    fn queryKittyTextSizingSupport(self: *Terminal) !bool {
        if (!looksLikeKittyTerminal()) return false;

        const cpr = "\x1b[6n";
        // CR, CPR, draw 2-cell space via kitty OSC 66 width-only, CPR.
        const probe = "\r" ++ cpr ++ "\x1b]66;w=2; \x07" ++ cpr;
        try self.writeBytes(probe);
        try self.flush();

        var buf: [512]u8 = undefined;
        var len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 250;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 40) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, buf.len - len);
            if (copy_len > 0) {
                @memcpy(buf[len .. len + copy_len], chunk[0..copy_len]);
                len += copy_len;
            }

            if (parseTwoCprColumns(buf[0..len])) |cols| {
                return cols.second == cols.first + 2;
            }
        }

        return false;
    }

    fn parseTwoCprColumns(bytes: []const u8) ?struct { first: usize, second: usize } {
        var idx: usize = 0;
        var found: [2]usize = .{ 0, 0 };
        var count: usize = 0;

        while (idx < bytes.len and count < 2) {
            const esc = std.mem.indexOfPos(u8, bytes, idx, "\x1b[") orelse break;
            var i = esc + 2;

            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
            if (i >= bytes.len or bytes[i] != ';') {
                idx = esc + 1;
                continue;
            }
            i += 1;

            const col_start = i;
            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
            if (i >= bytes.len or bytes[i] != 'R' or col_start == i) {
                idx = esc + 1;
                continue;
            }

            const col = std.fmt.parseInt(usize, bytes[col_start..i], 10) catch {
                idx = esc + 1;
                continue;
            };
            found[count] = col;
            count += 1;
            idx = i + 1;
        }

        if (count == 2) {
            return .{ .first = found[0], .second = found[1] };
        }
        return null;
    }

    fn isInsideMultiplexer() bool {
        return envVarExists("TMUX") or envVarExists("ZELLIJ") or envVarContains("TERM", "screen");
    }

    fn drainInput(self: *Terminal) void {
        var buf: [128]u8 = undefined;
        while (true) {
            const n = self.readInput(&buf, 0) catch return;
            if (n == 0) return;
        }
    }

    fn termFeaturesContain(features: []const u8, needle: []const u8) bool {
        if (features.len == 0 or needle.len == 0) return false;

        var i: usize = 0;
        while (i < features.len) {
            if (!std.ascii.isUpper(features[i])) {
                i += 1;
                continue;
            }

            var j = i + 1;
            while (j < features.len and std.ascii.isLower(features[j])) : (j += 1) {}
            const code = features[i..j];

            while (j < features.len and std.ascii.isDigit(features[j])) : (j += 1) {}
            if (std.mem.eql(u8, code, needle)) return true;

            i = j;
        }

        return false;
    }

    fn indexOfOscTerminator(bytes: []const u8, start: usize) ?usize {
        var i = start;
        while (i < bytes.len) : (i += 1) {
            if (bytes[i] == 0x07) return i;
            if (bytes[i] == 0x1b and i + 1 < bytes.len and bytes[i + 1] == '\\') {
                return i;
            }
        }
        return null;
    }

    fn indexOfSt(bytes: []const u8, start: usize) ?usize {
        var i = start;
        while (i + 1 < bytes.len) : (i += 1) {
            if (bytes[i] == 0x1b and bytes[i + 1] == '\\') return i;
        }
        return null;
    }

    fn isKnownUnicodeWidthTerminal() bool {
        // Terminals known to use grapheme-aware width by default.
        return envVarEquals("TERM_PROGRAM", "WezTerm") or
            envVarEquals("TERM_PROGRAM", "iTerm.app") or
            envVarContains("TERM", "wezterm") or
            envVarContains("TERM", "ghostty");
    }

    fn looksLikeKittyTerminal() bool {
        return envVarExists("KITTY_WINDOW_ID") or envVarContains("TERM", "kitty");
    }

    fn looksLikeIterm2Terminal() bool {
        return envVarEquals("TERM_PROGRAM", "iTerm.app") or
            envVarEquals("LC_TERMINAL", "iTerm2");
    }

    fn looksLikeSixelTerminal() bool {
        return envVarContains("TERM", "sixel") or
            envVarContains("TERM", "mlterm") or
            envVarContains("TERM", "yaft") or
            envVarContains("TERM", "contour");
    }

    fn isLikelyFullSixelSequence(bytes: []const u8) bool {
        if (bytes.len == 0) return false;
        return std.mem.startsWith(u8, bytes, ansi.DCS) or bytes[0] == 0x90;
    }

    fn isSixelDataPath(path: []const u8) bool {
        return std.mem.endsWith(u8, path, ".sixel") or
            std.mem.endsWith(u8, path, ".SIXEL") or
            std.mem.endsWith(u8, path, ".six") or
            std.mem.endsWith(u8, path, ".SIX");
    }

    fn commandExists(name: []const u8) bool {
        const argv = [_][]const u8{ name, "--version" };
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &argv,
            .max_output_bytes = 1024,
        }) catch return false;
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        return true;
    }

    fn envVarExists(name: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return value.len > 0;
    }

    fn envVarEquals(name: []const u8, expected: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return std.ascii.eqlIgnoreCase(value, expected);
    }

    fn envVarContains(name: []const u8, needle: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return std.mem.indexOf(u8, value, needle) != null;
    }

    /// Simple writer struct for compatibility
    pub const Writer = struct {
        terminal: *Terminal,

        pub fn writeAll(self: Writer, bytes: []const u8) !void {
            try self.terminal.writeBytes(bytes);
        }

        pub fn print(self: Writer, comptime fmt: []const u8, args: anytype) !void {
            var buf: [256]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, fmt, args) catch return;
            try self.terminal.writeBytes(result);
        }
    };
};
