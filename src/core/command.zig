//! Command system for the ZigZag TUI framework.
//! Commands represent side effects and actions to be performed.

const std = @import("std");

/// Parameters for image rendering by file path.
pub const ImagePlacement = enum {
    /// Use the current cursor position.
    cursor,
    /// Draw from top-left corner.
    top_left,
    /// Draw from top-center using width hint.
    top_center,
    /// Center using provided width/height cell hints.
    center,
};

/// Parameters for image rendering by file path.
pub const ImageFile = struct {
    path: []const u8,
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    placement: ImagePlacement = .top_left,
    /// Optional absolute row (0-indexed). Overrides anchor row when provided.
    row: ?u16 = null,
    /// Optional absolute column (0-indexed). Overrides anchor column when provided.
    col: ?u16 = null,
    /// Signed row offset (in terminal cells) applied after anchor/absolute position.
    row_offset: i16 = 0,
    /// Signed column offset (in terminal cells) applied after anchor/absolute position.
    col_offset: i16 = 0,
    preserve_aspect_ratio: bool = true,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

/// Backward-compatible alias for existing Kitty-only APIs.
pub const KittyImageFile = ImageFile;

/// Command type parameterized by the user's message type
pub fn Cmd(comptime Msg: type) type {
    return union(enum) {
        /// No operation
        none,

        /// Quit the application
        quit,

        /// Request a tick after the specified duration (nanoseconds)
        tick: u64,

        /// Request repeating tick at interval (nanoseconds)
        every: u64,

        /// Execute a batch of commands
        batch: []const Cmd(Msg),

        /// Execute commands in sequence (wait for each to complete)
        sequence: []const Cmd(Msg),

        /// Send a message to the update function
        msg: Msg,

        /// Execute a custom function that produces a message
        perform: *const fn () ?Msg,

        /// Suspend the program (Ctrl+Z behavior)
        suspend_process,

        /// Runtime terminal commands
        enable_mouse,
        disable_mouse,
        show_cursor,
        hide_cursor,
        enter_alt_screen,
        exit_alt_screen,
        set_title: []const u8,

        /// Print a line above the program output
        println: []const u8,

        /// Draw an image file using the best available protocol (Kitty, iTerm2, Sixel)
        image_file: ImageFile,

        /// Draw an image file via Kitty graphics protocol (no-op if unsupported)
        kitty_image_file: KittyImageFile,

        const Self = @This();

        /// Create a none command
        pub fn none_cmd() Self {
            return .none;
        }

        /// Create a quit command
        pub fn quit_cmd() Self {
            return .quit;
        }

        /// Request a tick after milliseconds
        pub fn tickMs(ms: u64) Self {
            return .{ .tick = ms * std.time.ns_per_ms };
        }

        /// Request a tick after seconds
        pub fn tickSec(sec: u64) Self {
            return .{ .tick = sec * std.time.ns_per_s };
        }

        /// Request a repeating tick every `ms` milliseconds
        pub fn everyMs(ms: u64) Self {
            return .{ .every = ms * std.time.ns_per_ms };
        }

        /// Request a repeating tick every `sec` seconds
        pub fn everySec(sec: u64) Self {
            return .{ .every = sec * std.time.ns_per_s };
        }

        /// Create a batch of commands
        pub fn batchOf(cmds: []const Self) Self {
            return .{ .batch = cmds };
        }

        /// Create a sequence of commands
        pub fn sequenceOf(cmds: []const Self) Self {
            return .{ .sequence = cmds };
        }

        /// Send a message
        pub fn send(message: Msg) Self {
            return .{ .msg = message };
        }

        /// Execute a function to get a message
        pub fn performFn(func: *const fn () ?Msg) Self {
            return .{ .perform = func };
        }

        /// Check if command is none
        pub fn isNone(self: Self) bool {
            return self == .none;
        }

        /// Check if command is quit
        pub fn isQuit(self: Self) bool {
            return self == .quit;
        }
    };
}

/// Standard commands without message type
pub const StandardCmd = union(enum) {
    none,
    quit,
    tick: u64,
    set_title: []const u8,
    enable_mouse,
    disable_mouse,
    show_cursor,
    hide_cursor,
    enter_alt_screen,
    exit_alt_screen,
    image_file: ImageFile,
    kitty_image_file: KittyImageFile,
};

/// Combine multiple commands into a batch
pub fn batch(comptime Msg: type, cmds: []const Cmd(Msg)) Cmd(Msg) {
    return .{ .batch = cmds };
}

/// Combine multiple commands into a sequence
pub fn sequence(comptime Msg: type, cmds: []const Cmd(Msg)) Cmd(Msg) {
    return .{ .sequence = cmds };
}

/// Create a tick command with millisecond duration
pub fn tick(comptime Msg: type, ms: u64) Cmd(Msg) {
    return Cmd(Msg).tickMs(ms);
}

/// Create a tick command that fires every frame
pub fn everyFrame(comptime Msg: type) Cmd(Msg) {
    return Cmd(Msg).tickMs(16); // ~60fps
}
