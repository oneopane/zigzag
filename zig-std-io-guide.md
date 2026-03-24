# Zig `std.Io` — a practical, source-linked guide (Zig 0.16.0-dev)

> This guide targets **Zig 0.16.0-dev** (the version in this repo’s toolchain: `0.16.0-dev.2623+27eec9bd6`).
>
> `std.Io` is still evolving quickly. When something in this document feels surprising, treat it as “what the standard library does today” and confirm against the current stdlib sources.

## What `std.Io` is (mental model)

`std.Io` is a **single cross-platform interface** that centralizes:

- I/O operations (files, directories, networking, terminals)
- concurrency primitives (mutex/condition/event/futex, queues)
- time (clocks, sleeps, timeouts)
- async/concurrent task scheduling, cancellation, batching
- process management and other OS services

At the type level, `std.Io` is essentially:

```zig
const Io = struct {
    userdata: ?*anyopaque,
    vtable: *const Io.VTable,
};
```

The **implementation** lives behind `Io.VTable`. You choose an implementation (e.g. `std.Io.Threaded`) and then pass around a value of type `std.Io` to any code that wants to do I/O or blocking/concurrent work.

Why this design matters:

- Library code can be written against `std.Io` without hardcoding “threads vs event loop vs OS backend”.
- The stdlib can route a high-level operation (like “stream a file into a socket”) to an optimal syscall (`sendfile`, `copy_file_range`, etc.) when available.
- Cancellation and concurrency become *part of the interface*, not ad-hoc conventions.

Primary source entry point (read this first):
- Zig stdlib: `lib/std/Io.zig` (top-level interface and most concurrency/time primitives)

## The layers: `Io` vs `Io.Reader`/`Io.Writer` vs endpoint wrappers

A recurring pattern in `std.Io` is:

1) **An endpoint wrapper type** (e.g. `std.Io.File.Reader` / `std.Io.File.Writer`) stores endpoint state (fd/handle, seek position, error memoization, mode selection…).
2) It exposes a field named `interface` of type `std.Io.Reader` or `std.Io.Writer`.
3) The `interface` value contains a buffer and a vtable for generic buffered operations.

Example from stdlib:
- `std.Io.File.Writer` contains `interface: Io.Writer` and implements `Io.Writer.VTable.drain`/`sendFile`.

This layering is why you often see code like:

```zig
var buf: [4096]u8 = undefined;
var fw = std.Io.File.stdout().writer(io, &buf);
try fw.interface.writeAll("hello\n");
try fw.interface.flush();
```

In this repo, you’ll see the same pattern in `libvaxis` (e.g. `Tty.writer()` returning a `*std.Io.Writer`).

## Choosing an `Io` implementation

### 1) `std.Io.Threaded` (the “works everywhere” implementation)

`std.Io.Threaded` implements the `std.Io` vtable using OS blocking syscalls plus a thread pool for concurrency.

Key constructors:

- `std.Io.Threaded.init(gpa, .{ ... }) -> Threaded`
- `threaded.io() -> std.Io`
- `threaded.deinit()`

There is also a no-concurrency convenience singleton:

- `std.Io.Threaded.init_single_threaded` (static value)
- `std.Io.Threaded.global_single_threaded` (pointer to a global instance)

Notes:
- `async` has weaker guarantees than `concurrent` and can work with more implementations.
- `concurrent` may return `error.ConcurrencyUnavailable` if the implementation cannot or will not schedule the task.

### 2) “Evented” implementations (`Uring` / `Kqueue` / `Dispatch`)

`std.Io.Evented` is an alias chosen at comptime based on OS + fiber support:

- Linux: `std.Io.Uring`
- BSDs: `std.Io.Kqueue`
- Apple platforms: `std.Io.Dispatch`

This path is currently gated by `std.Io.fiber.supported` (architectures: aarch64/x86_64 in this toolchain).

These implementations are where you typically get:
- high-scale async I/O without dedicating a thread per blocking operation
- batched submission/completion models matching `Io.Operation`/`Io.Batch`

If you want maximal I/O throughput/parallelism, you should expect to eventually target one of these (when suitable for your platform + workload), but **`Threaded` is the easiest baseline**.

## Quick start: building a minimal “real” `Io` in an application

```zig
const std = @import("std");

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();

    const io = threaded.io();

    var out_buf: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buf);
    defer out.interface.flush() catch {};

    try out.interface.print("pid={d}\n", .{std.process.getPid()});
}
```

Notes:
- **Buffers are explicit**: you provide the buffer storage for file readers/writers.
- The concrete `File.Writer` wrapper is `out`; the generic buffered interface is `out.interface`.

## `Io.Writer`: buffered output, vectored writes, sendfile

`std.Io.Writer` is a *generic buffered writer* with a vtable:

- `drain(w, data, splat)` is the only required primitive.
- `sendFile(w, file_reader, limit)` is optional (defaults to `error.Unimplemented`).
- `flush(w)` and `rebase(w, ...)` have defaults but can be specialized.

Core operations you’ll use most:

- `write(bytes) -> !usize` (may short-write)
- `writeAll(bytes) -> !void` (loops until done)
- `print(comptime fmt, args) -> !void` (formatted output)
- `flush() -> !void`

Buffer mechanics:

- `Writer.buffer` is storage.
- `Writer.end` is how many bytes are currently buffered (0..buffer.len).
- Writes try to buffer first; when buffer is full, they call `vtable.drain`.

### “Max performance” output patterns

1) **Keep buffers reasonably sized** (4–64 KiB typical).
2) **Prefer `writeSplatHeader` / vectored forms** when you naturally have multiple slices.
3) **Prefer `sendFile`** for file→socket/file→pipe copy paths when available.

Example: copying a file to stdout efficiently

```zig
var in_buf: [64 * 1024]u8 = undefined;
var out_buf: [64 * 1024]u8 = undefined;

var file = try std.Io.Dir.cwd().openFile(io, "data.bin", .{ .mode = .read_only });
defer file.close(io);

var r = file.reader(io, &in_buf);
var w = std.Io.File.stdout().writer(io, &out_buf);

defer w.interface.flush() catch {};

_ = try r.interface.streamRemaining(&w.interface);
```

Why this is good:
- The `File.Reader` stream path attempts `Writer.sendFile` first; on many OSes this becomes a kernel-level copy.

## `Io.Reader`: buffered input + “peek/toss” parsing style

`std.Io.Reader` is a buffered reader with a vtable:

- `stream(r, w, limit)` is the core primitive. It *streams bytes into a Writer*.
- `readVec(r, data)` reads into one or more buffers (has a default implementation via `stream`).
- `discard` and `rebase` have defaults.

You typically interact with it via helper methods:

- `readVec(data) -> !usize`
- `readVecAll(data) -> !void`
- `peek(n) -> ![]u8` (ensure n buffered, return a slice)
- `toss(n)` (advance after peeking)
- `take(n) -> ![]u8` (peek + toss)
- `fill(n) -> !void` (ensure at least n bytes buffered)
- `allocRemaining(gpa, limit) -> ![]u8`
- `streamRemaining(w) -> !usize`

### “Max performance” input patterns

For parsers/protocol decoders, `peek`/`toss` is the intended style:

```zig
try r.fill(4);
const header = try r.peek(4);
// parse header without copying
r.toss(4);
```

Advantages:
- avoids per-field tiny reads
- keeps data contiguous for fast parsing

Caveat:
- `peek` asserts the reader’s buffer is large enough for the requested `n`.
  If you need to peek up to N bytes, allocate the reader buffer to at least N.

## Files and directories (`std.Io.File`, `std.Io.Dir`)

### Opening and closing

- `std.Io.Dir.cwd()` returns a handle for the process cwd.
- `dir.openFile(io, path, flags) -> !File`
- `dir.createFile(io, path, flags) -> !File`
- `file.close(io)`

The `Io` implementation owns the syscalls; `Dir`/`File` are just handles.

### Creating file readers/writers

- `file.reader(io, buffer) -> File.Reader`
- `file.writer(io, buffer) -> File.Writer`

Both wrappers:
- expose `interface: std.Io.Reader` / `std.Io.Writer`
- memoize “mode” decisions (positional vs streaming; simple fallbacks)
- store detailed errors in wrapper fields (the `interface` error set is intentionally generic: `ReadFailed`/`WriteFailed`)

### Positional vs streaming

`File.Reader` / `File.Writer` try to use **positional** syscalls when possible (pread/pwrite variants), because:

- it’s more thread-safe (doesn’t mutate global file offset)
- can avoid races with other threads using the same descriptor

If the OS indicates positional ops are unsupported (e.g. `error.Unseekable`), the wrapper falls back to streaming mode.

## Time: clocks, timestamps, timeouts, sleep

`std.Io` defines:

- `Io.Clock` (real vs monotonic)
- `Io.Timestamp` and `Io.Duration`
- `Io.Timeout` (none / duration / timestamp)
- `Io.sleep(io, duration, clock) -> Cancelable!void`

In this repo you’ll see patterns like:

```zig
try std.Io.sleep(io, .fromMillis(16), .monotonic);
```

## Cancellation: `error.Canceled` as a first-class control path

Many `Io` functions include `Io.Cancelable` in their error set, which is:

```zig
pub const Cancelable = error{ Canceled };
```

Key ideas:

- Cancellation is delivered at **cancellation points** (calls into `Io` that include `error.Canceled`).
- Ignoring `error.Canceled` is usually a bug; the stdlib tries to enforce consistent propagation.

Tools:

- `io.checkCancel()` — explicit cancellation point for CPU-bound loops.
- `io.swapCancelProtection(.blocked/.unblocked)` — temporarily block cancellation observation.
- `io.recancel()` — “re-arm” cancellation after a cancellation point.

## Concurrency and async tasks

### `Io.async` vs `Io.concurrent`

- `io.async(func, args) -> Future(Result)`
  - `func` may execute immediately.
  - more portable; can work on implementations that don’t have real parallelism.

- `io.concurrent(func, args) -> !Future(Result)`
  - stronger guarantees; may fail with `error.ConcurrencyUnavailable`.

### Futures

A `Future(T)` is a tiny handle that stores:

- an “eager” result slot
- an optional `AnyFuture` pointer used by the implementation

You complete it via:

- `future.await(io)`
- `future.cancel(io)`

### Groups and Select

- `Io.Group` manages a set of tasks and awaits/cancels them as a whole.
- `Io.Select(Union)` is a higher-level pattern for “spawn tasks, get first completion result” using an internal queue.

If you’re building apps with multiple concurrent I/O activities (e.g. input reader + renderer + network), `Group`/`Select` are the intended primitives.

## `Io.Operation` and `Io.Batch`: the low-level “submit/complete” core

`Io.Operation` is a tagged union representing a single low-level op.

Examples currently in `Io.Operation`:

- `file_read_streaming`
- `file_write_streaming`
- `device_io_control` (ioctl/NtDeviceIoControlFile)

`Io.operate(io, op)` performs one operation.

`Io.Batch` lets you submit many `Operation`s and then await completions in bulk.

Why you care:

- Evented backends (io_uring/kqueue/etc.) naturally map to this.
- Even on `Threaded`, batch APIs can let the implementation schedule work efficiently.

Rule of thumb:
- Use `File.Reader`/`File.Writer` + `Io.Reader`/`Io.Writer` first.
- Reach for `Operation`/`Batch` when you need explicit control over syscall-level sequencing, timeouts, and completion iteration.

## Terminal output: `std.Io.Terminal`

`std.Io.Terminal` is a small helper that writes either:

- ANSI escape sequences (`Mode.escape_codes`)
- Windows console API calls (`Mode.windows_api`)
- or nothing (`Mode.no_color`)

Detection:

```zig
const mode = try std.Io.Terminal.Mode.detect(io, std.Io.File.stderr(), NO_COLOR, CLICOLOR_FORCE);
```

Then:

```zig
var stderr_buf: [4096]u8 = undefined;
var fw = std.Io.File.stderr().writer(io, &stderr_buf);
var term: std.Io.Terminal = .{ .writer = &fw.interface, .mode = mode };

try term.setColor(.red);
try fw.interface.writeAll("error\n");
try term.setColor(.reset);
try fw.interface.flush();
```

## Implementing your own `Io.Reader` / `Io.Writer`

You normally do **not** implement a whole `Io` backend. Instead, you implement *Reader/Writer adapters*.

### Implementing a custom `Io.Writer`

You provide:

- `VTable.drain(w, data, splat) -> Writer.Error!usize`

and optionally:

- `sendFile`
- `flush`
- `rebase`

Key invariants:

- `data.len` is non-zero when `drain` is called.
- `data` slices may alias each other; they must not alias `w.buffer`.
- `w.buffer[0..w.end]` must be treated as already-buffered “header” bytes.
- If you partially drain, use `std.Io.Writer.consume(w, n)` to shift remaining buffered bytes.

A very small example: an in-memory “counting” sink can be built using `std.Io.Writer.Discarding` (already provided by stdlib).

### Implementing a custom `Io.Reader`

You provide:

- `VTable.stream(r, w, limit) -> Reader.StreamError!usize`

and optionally:

- `discard`
- `readVec`
- `rebase`

Key invariants:

- The reader tracks a logical position using `seek`/`end` inside `r.buffer`.
- `stream` is allowed to write either into `w` or into `r.buffer` (by adjusting `seek`/`end`).

If you’re building protocol decoders, consider wrapping an underlying reader and adding:

- `limited` (stdlib provides `Reader.Limited`)
- hashing/teeing (stdlib provides `Reader.hashed` and Writer hashing variants)

## Differences vs legacy `std.io`

This repository contains both:

- `std.Io` (capital-I) — the modern interface described here.
- some dependency/bench code still using `std.io` (lowercase) APIs.

Practical guidance:

- For new code in this repo, prefer **`std.Io`**.
- When integrating older dependencies that expose `std.io.Reader/Writer`, treat them as separate ecosystems and adapt at boundaries.

## How this repo uses `std.Io` (patterns worth copying)

From the repo scan:

- Many APIs accept a `*std.Io.Writer` (e.g. rendering/terminal control in `src/Vaxis.zig`).
- The TTY abstraction returns a writer interface rather than a concrete file handle (`src/tty.zig`).
- Parsers consume `std.Io.Reader` and use `Limit` to keep scanning bounded (`src/widgets/terminal/Parser.zig`).

These patterns align with `std.Io`’s intent:

- pass `std.Io` and `*std.Io.Writer`/`*std.Io.Reader` around, not concrete OS handles
- centralize buffering at boundaries (TTY/file/socket)
- let the stdlib choose optimal syscalls (`sendfile`, positional I/O, etc.)

## Checklist: “maximally utilize `std.Io`”

- Pick the right `Io` backend early (`Threaded` first; evented later).
- Keep buffers explicit and sized for your workload.
- Use `Reader.streamRemaining` / `Writer.sendFile` paths for bulk transfers.
- Use `peek/toss` parsing to reduce copying.
- Make cancellation part of your design (`error.Canceled` flows).
- Use `Group` / `Select` for multi-activity apps.
- Reach for `Operation`/`Batch` only when you need syscall-level control.

---

### Source pointers (Zig 0.16.0-dev stdlib)

- `std/Io.zig` — the `Io` interface, vtable, `Operation`, `Batch`, cancellation, clocks, futex/mutex/condition/queue
- `std/Io/Reader.zig` — buffered reader interface + helper methods (`peek`, `fill`, `streamRemaining`, alloc helpers)
- `std/Io/Writer.zig` — buffered writer interface + helper methods (`writeAll`, `print`, `sendFile`, `Allocating`, `Discarding`)
- `std/Io/File.zig`, `std/Io/File/Reader.zig`, `std/Io/File/Writer.zig` — file handles and adapters that implement Reader/Writer
- `std/Io/Dir.zig` — directory handles and filesystem operations on top of `Io`
- `std/Io/Threaded.zig` — thread-based `Io` backend
- `std/Io/Uring.zig` / `Kqueue.zig` / `Dispatch.zig` — evented backends (platform-specific)
