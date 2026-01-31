# ZigZag

A delightful TUI framework for Zig, inspired by [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lipgloss](https://github.com/charmbracelet/lipgloss).

## Features

- **Elm Architecture** - Model-Update-View pattern for predictable state management
- **Rich Styling** - Comprehensive styling system with colors, borders, padding, and alignment
- **Pre-built Components** - TextInput, TextArea, List, Table, Viewport, Progress, Spinner, and more
- **Cross-platform** - Works on macOS, Linux, and Windows
- **Zero Dependencies** - Pure Zig with no external dependencies

## Installation

Add ZigZag to your `build.zig.zon`:

```zig
.dependencies = .{
    .zigzag = .{
        .url = "https://github.com/meszmate/zigzag/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zigzag = b.dependency("zigzag", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigzag", zigzag.module("zigzag"));
```

## Quick Start

```zig
const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    count: i32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .count = 0 };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .up => self.count += 1,
                .down => self.count -= 1,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const style = zz.Style{}.bold(true).fg(zz.Color.cyan());
        const text = std.fmt.allocPrint(ctx.allocator, "Count: {d}\n\nPress q to quit", .{self.count}) catch "Error";
        return style.render(ctx.allocator, text) catch text;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();
    try program.run();
}
```

## Core Concepts

### The Elm Architecture

ZigZag uses the Elm Architecture (Model-Update-View):

1. **Model** - Your application state
2. **Msg** - Messages that describe state changes
3. **init** - Initialize your model
4. **update** - Handle messages and update state
5. **view** - Render your model to a string

### Commands

Commands let you perform side effects:

```zig
return .quit;              // Quit the application
return .none;              // Do nothing
return .{ .tick = ns };    // Request a tick after `ns` nanoseconds
```

### Styling

The styling system is inspired by Lipgloss:

```zig
const style = zz.Style{}
    .bold(true)
    .italic(true)
    .fg(zz.Color.cyan())
    .bg(zz.Color.black())
    .paddingAll(1)
    .marginAll(2)
    .borderAll(zz.Border.rounded)
    .borderForeground(zz.Color.magenta())
    .width(40)
    .align(.center);

const output = try style.render(allocator, "Hello, World!");
```

### Colors

```zig
// Basic ANSI colors
zz.Color.red()
zz.Color.cyan()
zz.Color.brightGreen()

// 256-color palette
zz.Color.color256(123)
zz.Color.gray(15)  // 0-23 grayscale

// True color (24-bit)
zz.Color.rgb(255, 128, 64)
zz.Color.hex("#FF8040")
```

### Borders

```zig
zz.Border.normal    // ┌─┐
zz.Border.rounded   // ╭─╮
zz.Border.double    // ╔═╗
zz.Border.thick     // ┏━┓
zz.Border.ascii     // +-+
```

## Components

### TextInput

Single-line text input with cursor and validation:

```zig
var input = zz.TextInput.init(allocator);
input.setPlaceholder("Enter name...");
input.setPrompt("> ");
input.handleKey(key_event);
const view = try input.view(allocator);
```

### TextArea

Multi-line text editor:

```zig
var editor = zz.components.TextArea.init(allocator);
editor.setSize(80, 24);
editor.line_numbers = true;
editor.handleKey(key_event);
```

### List

Selectable list with optional filtering:

```zig
var list = zz.List(MyItem).init(allocator);
list.multi_select = true;
try list.addItem(.{ .value = item, .title = "Item 1" });
list.handleKey(key_event);
```

### Viewport

Scrollable content area:

```zig
var viewport = zz.Viewport.init(allocator, 80, 24);
try viewport.setContent(long_text);
viewport.handleKey(key_event);  // Supports j/k, Page Up/Down, etc.
```

### Progress

Progress bar:

```zig
var progress = zz.Progress.init();
progress.setWidth(40);
progress.setPercent(75);
const bar = try progress.view(allocator);
```

### Spinner

Animated loading indicator:

```zig
var spinner = zz.Spinner.init();
spinner.update(elapsed_ns);
const view = try spinner.viewWithTitle(allocator, "Loading...");
```

### Table

Tabular data display:

```zig
var table = zz.Table(3).init(allocator);
table.setHeaders(.{ "Name", "Age", "City" });
try table.addRow(.{ "Alice", "30", "NYC" });
try table.addRow(.{ "Bob", "25", "LA" });
```

### More Components

- **Help** - Display key bindings
- **Paginator** - Pagination controls
- **Timer** - Countdown/stopwatch
- **FilePicker** - File system navigation

## Layout

### Join

Combine multiple strings:

```zig
// Horizontal (side by side)
const row = try zz.joinHorizontal(allocator, &.{ left, middle, right });

// Vertical (stacked)
const col = try zz.joinVertical(allocator, &.{ top, middle, bottom });
```

### Measure

Get text dimensions (ANSI-aware):

```zig
const w = zz.width("Hello");           // 5
const h = zz.height("Line 1\nLine 2"); // 2
```

### Place

Position content in a bounding box:

```zig
const centered = try zz.place.place(allocator, 80, 24, .center, .middle, content);
```

## Examples

Run the examples:

```bash
zig build run-hello_world
zig build run-counter
zig build run-todo_list
zig build run-text_editor
zig build run-file_browser
zig build run-dashboard
```

## Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

## Cross-compilation

```bash
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86_64-windows
```

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - The original Go TUI framework
- [Lipgloss](https://github.com/charmbracelet/lipgloss) - Style definitions for terminal applications
- [The Elm Architecture](https://guide.elm-lang.org/architecture/) - The pattern that inspired it all
