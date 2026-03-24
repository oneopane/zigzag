# Zig 0.16 migration plan for ZigZag

## Executive summary

This document turns the raw breakage inventory in `docs/zig-0.16-migration-inventory.md` into an implementation-oriented migration plan.

The key conclusion is:

- **not every breakage is an `std.Io` issue**, but
- **several of the highest-impact breakages are best understood as consequences of the broader Zig 0.16 `std.Io` redesign**, not as isolated symbol renames.

For this repo, the important distinction is:

- **C3 and C4 are directly `std.Io`-driven**
- **C2 and C5 should be fixed in a way that aligns with the new `std.Io` model**, even though their immediate breakages are not literally just `std.io` → `std.Io`
- **C1 is unrelated to `std.Io`** and should be kept narrow and mechanical

### Recommended repo-wide decisions before editing code

1. **Dynamic string building / owned buffer construction**
   - Keep `std.array_list.Managed(u8)` for now.
   - Replace broken `.writer()` usage primarily with `append`, `appendSlice`, and `print`.
   - Reserve `std.Io.Writer.Allocating` for cases that genuinely benefit from a `*std.Io.Writer` interface.

2. **Fixed-buffer formatting**
   - Standardize on `std.Io.Writer.fixed` for stack-buffer formatting.
   - In terminal/image protocol code, consider one small local helper rather than repeating low-level buffer plumbing.

3. **Time / clocks / deadlines**
   - Treat time migration as one explicit design decision.
   - Separate three semantics: monotonic elapsed time, monotonic deadlines, and wall-clock timestamps.
   - Prefer a small repo-local compatibility layer over a public API refactor to thread `std.Io` through everything immediately.

4. **Custom formatter conventions**
   - Standardize on a current formatter shape that uses `std.fmt.Options` and `*std.Io.Writer`.
   - Update tests to exercise formatting through a current writer/formatting path, not the old direct-call convention.

5. **Example bootstrap / allocator policy**
   - For this migration, keep example entrypoints narrow and mechanical.
   - Do **not** treat this as the moment to refactor all examples to `main(init: std.process.Init)` unless we explicitly choose that scope.

### Recommended migration order

1. Decide the repo-wide patterns above.
2. Patch the core library first:
   - C2 → C3 → C5 → C4
3. Run `zig test src/root.zig` repeatedly during library work.
4. Then run `zig build test`.
5. Patch examples/docs last:
   - C1 plus remaining example-local C2 sites
6. Finish with `zig build`.

This ordering minimizes churn by solving the broad string/writer breakages first, delaying the more semantic time migration until the surrounding writer patterns are stable.

---

## How to use this document with the inventory

Use the two docs together:

- `docs/zig-0.16-migration-inventory.md`
  - canonical list of currently known breakages, affected files, and evidence
- `docs/zig-0.16-migration-plan.md` (this file)
  - recommended fix strategy, standard patterns, and design decisions

In short:

- the **inventory** answers: **what is broken and where?**
- this **plan** answers: **how should we fix it in this repo, with minimal churn and sensible alignment to Zig 0.16?**

### Important note about `zig-std-io-guide.md`

`zig-std-io-guide.md` is the primary reference for the **new `std.Io` mental model**:

- `std.Io` centralizes I/O, time, cancellation, and concurrency
- in-memory formatting should use `std.Io.Writer.fixed` / `std.Io.Writer.Allocating`
- helpers should generally accept `*std.Io.Writer`
- modern application code often starts from `std.process.Init` / `init.io`

However, this guide is **conceptual and version-sensitive**. The local toolchain remains the source of truth for exact symbols.

Concrete example:

- the guide’s quick-start app example still shows `std.heap.GeneralPurposeAllocator`
- the local toolchain used by this repo does **not** provide that symbol

So the guide should drive **architecture and preferred patterns**, while the local toolchain and inventory drive **exact implementation choices**.

---

## What the `std.Io` guide changes for this repo

The `std.Io` guide has five practical implications for ZigZag:

### 1. `std.io` removal is only the surface symptom

The modern model is not just “capitalize `Io`”. It changes:

- how fixed-buffer formatting works
- how owned formatted output should be built
- where clocks/timeouts live
- what a modern writer-facing helper should accept

This matters most for **C2**, **C3**, **C4**, and **C5**.

### 2. Writers are explicit buffered interfaces

The guide emphasizes that modern writer code should prefer:

- `std.Io.Writer.fixed` for fixed buffers
- `std.Io.Writer.Allocating` for owned dynamic output
- passing `*std.Io.Writer` to helpers rather than copying writer structs by value

This gives us the right lens for deciding how to repair removed `ArrayList.writer()` usage.

### 3. Time is now part of the `std.Io` world

The guide explicitly places:

- clocks
- timestamps/durations
- timeouts
- sleep

under `std.Io`, not old `std.time` runtime helpers.

That means **C4 is not just a missing-symbol patch**. It is a semantic migration from “old `std.time` helpers” to “new clock/deadline model”.

### 4. Concrete wrappers vs generic interfaces should be kept distinct

The guide stresses that endpoint wrappers store extra state and richer errors, while the `interface` field is the generic buffered API.

For this repo, the practical lesson is:

- do **not** turn this migration into a repo-wide rewrite to generic `std.Io` everywhere
- keep working wrapper code as-is unless it is part of a broken class
- use `std.Io` concepts where they directly solve the current breakage

### 5. Avoid broad public API churn unless justified

The guide’s most idiomatic application shape is often:

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    _ = io;
    _ = gpa;
}
```

That is useful directionally, but applying it wholesale here would be a larger design refactor than is necessary to restore compatibility.

For this migration, the repo should prefer:

- **local, narrow fixes**
- **internal compatibility helpers where needed**
- **no public API redesign unless compile blockers force it**

---

## Classification of the migration classes (C1–C5)

| Class | Relation to new `std.Io` model | Fix nature | Repo implication |
|---|---|---|---|
| C1 allocator bootstrap in examples/docs | **Unrelated** | Safe mechanical | Fix narrowly; do not use it to justify broader app-entry refactors |
| C2 `std.array_list.Managed(...).writer()` removal | **Indirectly influenced** | Semi-mechanical with preferred pattern | Fix mainly with direct list methods; use `std.Io.Writer.Allocating` selectively |
| C3 `std.io.fixedBufferStream` / `stream.writer()` / `stream.getWritten()` | **Directly caused** | Semi-mechanical | Standardize on `std.Io.Writer.fixed` and optionally a local helper |
| C4 runtime time API migration from old `std.time` | **Directly caused** | Design decision | Treat as one clock/deadline policy, not a line-by-line rename |
| C5 custom formatter signature drift | **Indirectly influenced** | Safe mechanical once convention chosen | Use a modern formatter shape based on `*std.Io.Writer` |

---

## Cross-cutting design decisions to make once

## Decision A — Dynamic string building / owned buffer construction

### Recommended standard for this repo

**Default pattern:** keep existing `std.array_list.Managed(u8)` buffers and replace broken `.writer()` usage with:

- `append`
- `appendSlice`
- `print`
- `toOwnedSlice`

### Why

This minimizes churn because:

- `std.array_list.Managed(...)` still exists on the current toolchain
- `Managed.print(...)` still exists
- most broken callsites are local string assembly, not true generic-writer plumbing

### When to use `std.Io.Writer.Allocating`

Use it only when one of these is true:

- multiple helpers naturally want a `*std.Io.Writer`
- the function would become materially clearer if written as a writer pipeline
- a small compatibility/helper abstraction would remove a lot of duplicated logic in one subsystem

### What to avoid

- do **not** convert the repo wholesale from `Managed` to new `ArrayList` APIs as part of this migration
- do **not** replace every broken site with `Writer.Allocating` just because it exists
- do **not** pass `std.Io.Writer` by value through helpers if you introduce writer-based helpers; follow the guide and pass `*std.Io.Writer`

---

## Decision B — Fixed-buffer formatting

### Recommended standard for this repo

Use the modern fixed-writer pattern:

```zig
var buf: [N]u8 = undefined;
var w: std.Io.Writer = .fixed(&buf);
try w.print("...", .{...});
const bytes = w.buffered();
```

### Why

This is the closest modern replacement for the old:

```zig
var stream = std.io.fixedBufferStream(&buf);
const writer = stream.writer();
...
const bytes = stream.getWritten();
```

### Where to encapsulate it

Keep any helper local to the terminal/image subsystem.

The duplication is concentrated in:

- `src/terminal/ansi.zig`
- `src/terminal/terminal.zig`

A small local helper is justified there. A repo-wide helper probably is not.

---

## Decision C — Time / clocks / deadlines

### Recommended standard for this repo

Introduce one narrow internal time abstraction and use it consistently for the three time semantics already present in the repo:

1. **Monotonic elapsed time**
   - for frame timing / animation cadence / program runtime bookkeeping
2. **Monotonic deadlines**
   - for terminal probe loops and bounded waits
3. **Wall-clock time**
   - for logger timestamps

### Why

The guide makes clear that time in Zig 0.16 belongs to the `std.Io` model, but this repo does not currently expose `std.Io` throughout its public API.

A narrow internal abstraction lets us:

- choose the right semantics once
- hide toolchain-specific details behind a single file
- avoid a larger `Program` / `Terminal` public API refactor in the same migration

### Preferred migration stance

- **do** align the abstraction conceptually with `std.Io.Clock`, timestamps, and deadlines
- **do not** force `std.Io` into every existing public signature during this migration unless required

### What to avoid

- do not use wall-clock time for deadline loops
- do not collapse “elapsed”, “deadline”, and “real time” into one helper with muddy semantics
- do not line-edit old `std.time` usage without deciding what kind of clock each callsite really needs

---

## Decision D — Custom formatter conventions

### Recommended standard for this repo

Adopt one modern formatter shape consistently. Preferred default:

```zig
pub fn format(
    self: T,
    comptime fmt: []const u8,
    options: std.fmt.Options,
    writer: *std.Io.Writer,
) !void
```

### Why

This preserves the old intent while aligning with:

- current `std.fmt.Options`
- the guide’s recommendation to work with `*std.Io.Writer`
- current stdlib conventions for writer-facing formatting hooks

### Practical note

If a type truly never needs format/options behavior, a simpler formatter form may also be valid on current Zig. But for this repo, choosing the fuller signature keeps the migration clearer and more conservative.

### Testing convention

Where practical, tests should verify formatting through current formatting/writer machinery rather than directly calling the old signature shape.

---

## Decision E — Example app bootstrap / allocator policy

### Recommended standard for this repo

For this migration, use a **minimal-churn allocator policy** in examples and docs.

### Why

Although the guide presents `std.process.Init` / `init.io` as the modern application entrypoint, adopting that across all examples would create surface churn unrelated to the actual compile blockers.

### Recommendation

- choose one current allocator bootstrap pattern for examples/docs
- apply it consistently across all example mains and doc snippets
- defer broader example entrypoint modernization until after the repo builds cleanly again

### What to avoid

- do not mix “fix broken allocator bootstrap” with “redesign example app structure” unless we explicitly choose that scope

---

## Per-class analysis and repo-specific fix guidance

## C1 — allocator bootstrap in examples/docs

### Classification

- **Relation to `std.Io`: unrelated**
- **Fix type: safe mechanical**

### Immediate cause

The old example bootstrap uses `std.heap.GeneralPurposeAllocator`, which is gone on the current toolchain.

### Practical implication for this repo

Treat this as a narrow example/doc compatibility sweep.

Do **not** use C1 as justification to:

- refactor all examples to `main(init: std.process.Init)`
- thread `io: std.Io` into public APIs prematurely
- touch library code that already compiles or will compile once other classes are fixed

### Recommended repo approach

- pick one allocator bootstrap pattern
- apply it consistently in:
  - `23` example mains
  - `README.md`
  - `src/root.zig` doc snippet

### Concrete repo example

Current pattern in `examples/counter.zig`:

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
```

Recommended migration stance:
- keep the shape of the example intact
- only replace the allocator bootstrap pattern

---

## C2 — `std.array_list.Managed(...).writer()` removal

### Classification

- **Relation to `std.Io`: indirectly influenced**
- **Fix type: semi-mechanical with preferred pattern**

### Immediate cause

`std.array_list.Managed(u8)` no longer exposes `.writer()`.

### Why `std.Io` still matters here

The guide gives the modern writer-facing options:

- `std.Io.Writer.fixed`
- `std.Io.Writer.Allocating`
- helper APIs that accept `*std.Io.Writer`

That means C2 is not a pure symbol removal problem. We need to choose what this repo’s **standard output-building idiom** should be.

### Recommended repo approach

Use a two-tier rule:

#### Tier 1 — default and preferred
Use the existing managed buffer directly:

- `append`
- `appendSlice`
- `print`
- `toOwnedSlice`

This should fix the majority of C2 sites.

#### Tier 2 — selective use
Use `std.Io.Writer.Allocating` only where:

- a writer interface is actually useful
- helper factoring becomes materially cleaner
- one subsystem has enough repeated writer-style logic to justify it

### Why this is the right fit for ZigZag

This repo already has a strong pattern of:

- create byte buffer
- write text into it
- return owned slice

The inventory also shows `std.array_list.Managed(` remains broadly used but is **not itself a compile blocker**. So the safest move is to keep the container type and only change the broken writing access pattern.

### Generalized migration patterns

#### Pattern C2-A — local owned-string builder (preferred)

Old shape:

```zig
var result = std.array_list.Managed(u8).init(allocator);
const writer = result.writer();
try writer.writeAll("...");
try writer.print("...", .{...});
return result.toOwnedSlice();
```

Recommended new shape:

```zig
var result = std.array_list.Managed(u8).init(allocator);
try result.appendSlice("...");
try result.print("...", .{...});
return result.toOwnedSlice();
```

Use this when one function locally assembles text and returns an owned slice.

#### Pattern C2-B — writer-oriented helper path (secondary)

Old shape:

```zig
var result = std.array_list.Managed(u8).init(allocator);
const writer = result.writer();
try helper(writer, ...);
return result.toOwnedSlice();
```

Possible new direction:

```zig
var a = std.Io.Writer.Allocating.init(allocator);
defer a.deinit();
try helper(&a.writer, ...);
return try a.toOwnedSlice();
```

Use this only if the code genuinely benefits from helper functions taking `*std.Io.Writer`.

### Concrete repo examples

#### Example 1 — simple local builder: `src/layout/join.zig`

Current shape:

```zig
var result = std.array_list.Managed(u8).init(allocator);
const writer = result.writer();

for (0..max_height) |row| {
    if (row > 0) try writer.writeByte('\n');
    ...
    try writer.writeAll(line);
}
```

Recommended fix style:
- `writeByte('\n')` → `append('\n')`
- `writeAll(line)` → `appendSlice(line)`
- `print(...)` sites, if any, → `result.print(...)`

This is a textbook Tier-1 case.

#### Example 2 — nested builders: `src/components/menu_bar.zig`

Current shape:

```zig
var result = std.array_list.Managed(u8).init(allocator);
const writer = result.writer();

var bar_content = std.array_list.Managed(u8).init(allocator);
const bar_writer = bar_content.writer();
```

Recommended fix style:
- still prefer Tier 1 first
- keep nested `Managed(u8)` buffers
- replace each nested writer use with direct list methods

Only if this becomes too noisy should this subsystem introduce a local writer helper.

### Things not to do for C2

- do not turn C2 into a repo-wide migration off `std.array_list.Managed`
- do not standardize on `Writer.Allocating` if most functions are simpler as local list builders
- do not introduce a shared abstraction unless it clearly eliminates repeated boilerplate in one concentrated area

---

## C3 — `std.io.fixedBufferStream` / `stream.writer()` / `stream.getWritten()`

### Classification

- **Relation to `std.Io`: directly caused**
- **Fix type: semi-mechanical**

### Immediate cause

The repo uses the old fixed-buffer stream pattern from legacy `std.io`.

### Why this is directly `std.Io`-driven

The guide explicitly points to modern in-memory fixed-buffer output via `std.Io.Writer.fixed`.

So C3 is not just a rename from `std.io` to `std.Io`; it is a shift from one in-memory formatting idiom to another.

### Recommended repo approach

Adopt one standard fixed-buffer pattern:

```zig
var buf: [N]u8 = undefined;
var w: std.Io.Writer = .fixed(&buf);
try w.print("...", .{...});
const bytes = w.buffered();
```

### Generalized migration patterns

#### Pattern C3-A — direct fixed writer replacement

Old:

```zig
var stream = std.io.fixedBufferStream(&buf);
const writer = stream.writer();
try writer.print("...", .{...});
const bytes = stream.getWritten();
```

Recommended new form:

```zig
var w: std.Io.Writer = .fixed(&buf);
try w.print("...", .{...});
const bytes = w.buffered();
```

#### Pattern C3-B — local helper for parameter-string assembly

For repeated terminal protocol parameter builders, a local helper can encapsulate:

- creating a fixed writer
- formatting fields into it
- returning the written slice

This is justified specifically in `src/terminal/terminal.zig`, where the pattern repeats many times.

### Concrete repo examples

#### Example 1 — test helper path: `src/terminal/ansi.zig`

Current shape:

```zig
var buf: [128]u8 = undefined;
var stream = std.io.fixedBufferStream(&buf);
try osc52Encoded(stream.writer(), "c", "YQ==", .bel, .none);
try std.testing.expectEqualStrings("...", stream.getWritten());
```

Recommended fix style:
- replace the stream with one fixed writer
- pass the writer to `osc52Encoded`
- compare against the writer’s buffered slice

#### Example 2 — protocol params: `src/terminal/terminal.zig`

Current shape:

```zig
var params_buf: [256]u8 = undefined;
var stream = std.io.fixedBufferStream(&params_buf);
const params_writer = stream.writer();
...
try self.sendKittyGraphicsPayload(stream.getWritten(), image_data);
```

Recommended fix style:
- standardize on a fixed writer pattern
- optionally factor a tiny helper inside the terminal module for repeated param assembly

### Things not to do for C3

- do not introduce a repo-wide fixed-buffer abstraction if only terminal code needs it
- do not mix old `stream` mental model with new writer semantics; settle on one fixed-writer idiom and use it consistently

---

## C4 — runtime time API migration from old `std.time`

### Classification

- **Relation to `std.Io`: directly caused**
- **Fix type: design decision**

### Immediate cause

The old runtime helpers are gone from `std.time`:

- `std.time.Timer`
- `std.time.timestamp()`
- `std.time.milliTimestamp()`

### Why this is directly `std.Io`-driven

The guide explicitly places time, timestamps, durations, timeouts, and sleep inside `std.Io`.

That means C4 is best approached as a **clock/deadline design migration**, not a rename hunt.

### Recommended repo approach

Introduce one narrow internal compatibility layer that gives the repo exactly what it needs:

- monotonic-now / elapsed-time support
- monotonic-deadline support
- wall-clock-seconds support
- optional sleep helper if needed by the current code

This layer should hide whichever current Zig 0.16 time API is ultimately chosen after verifying the local stdlib in detail.

### Why a compatibility layer is preferable here

It gives us three benefits:

1. keeps public API churn low
2. centralizes toolchain-sensitive time code in one place
3. forces semantic clarity at each callsite

### Generalized migration patterns

#### Pattern C4-A — monotonic timestamp / elapsed-time helper

Old:

```zig
var clock = try std.time.Timer.start();
const start = clock.read();
...
const now = clock.read();
```

Recommended migration direction:
- use one repo-local monotonic timestamp representation
- compute elapsed time from monotonic timestamps, not wall-clock time

This should serve:
- `Program` frame timing
- animation cadence
- other elapsed-time bookkeeping

#### Pattern C4-B — monotonic deadline helper

Old:

```zig
const deadline_ms = std.time.milliTimestamp() + timeout_ms;
while (std.time.milliTimestamp() < deadline_ms) {
    ...
}
```

Recommended migration direction:
- construct a monotonic deadline once
- compare current monotonic time to that deadline
- keep deadline math monotonic-only

This should serve terminal capability probing and clipboard response polling.

#### Pattern C4-C — wall-clock timestamp helper

Old:

```zig
const now = std.time.timestamp();
```

Recommended migration direction:
- provide one wall-clock seconds helper specifically for logger timestamping

### Concrete repo examples

#### Example 1 — elapsed time in `src/core/program.zig`

Current shape:

```zig
clock: std.time.Timer,
...
var clock = try std.time.Timer.start();
const now = clock.read();
```

Recommended fix stance:
- do not patch this ad hoc
- move `Program` to the repo’s chosen monotonic time abstraction

#### Example 2 — deadline loops in `src/terminal/terminal.zig`

Current shape:

```zig
const deadline_ms = std.time.milliTimestamp() + timeout_ms;
while (std.time.milliTimestamp() < deadline_ms) {
    ...
}
```

Recommended fix stance:
- convert these loops to one monotonic-deadline helper pattern
- do not use wall-clock APIs here

#### Example 3 — logger timestamps in `src/core/log.zig`

Current shape:

```zig
const now = std.time.timestamp();
const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
```

Recommended fix stance:
- keep the wall-clock semantics
- move only the “how we get current real time” part behind the chosen compatibility layer

### Things not to do for C4

- do not use one generic `now()` for both monotonic deadlines and logger timestamps
- do not refactor the whole repo to explicit `io: std.Io` just to solve these three files, unless later work proves it necessary
- do not defer semantic choice until after editing callsites; choose the semantics first

---

## C5 — custom formatter signature drift

### Classification

- **Relation to `std.Io`: indirectly influenced**
- **Fix type: safe mechanical once convention is chosen**

### Immediate cause

The old formatter definitions use:

- `std.fmt.FormatOptions`
- `writer: anytype`

The current toolchain uses `std.fmt.Options`, and the guide points toward `*std.Io.Writer` as the modern writer-facing convention.

### Recommended repo approach

Standardize the custom formatters on:

```zig
pub fn format(
    self: T,
    comptime fmt: []const u8,
    options: std.fmt.Options,
    writer: *std.Io.Writer,
) !void
```

For `KeyEvent` and `MouseEvent`, keeping the unused `fmt`/`options` parameters is acceptable if it preserves compatibility and keeps the migration obvious.

### Concrete repo examples

#### Example 1 — `src/input/keys.zig`

Current shape:

```zig
pub fn format(
    self: KeyEvent,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void
```

Recommended fix stance:
- change only the formatter convention
- keep the rendering behavior the same

#### Example 2 — `tests/input_tests.zig`

Current direct call uses the old shape.

Recommended fix stance:
- update the test to use the new formatter convention and/or current formatting machinery
- avoid preserving the old direct-call pattern if it obscures the new conventions

### Things not to do for C5

- do not invent a repo-specific formatter convention different from current Zig patterns
- do not leave tests calling formatter functions in a legacy style if the production signature is updated

---

## Standardized patterns for this repo

The following should be treated as the implementation defaults unless a specific site justifies deviation.

### Pattern 1 — Local owned text assembly (default)

Use this for most component/view/layout renderers:

- `std.array_list.Managed(u8).init(allocator)`
- `append`, `appendSlice`, `print`
- `toOwnedSlice`

### Pattern 2 — Fixed stack-buffer formatting

Use this for terminal/image protocol parameter strings and tests that only need temporary stack-backed output:

- `var w: std.Io.Writer = .fixed(&buf)`
- `w.print(...)`
- `w.buffered()`

### Pattern 3 — Writer-oriented helper boundary

Only when helper factoring justifies it:

- helper signatures should take `*std.Io.Writer`
- if dynamic owned output is needed, build it with `std.Io.Writer.Allocating`

### Pattern 4 — Narrow internal time layer

Use one internal compatibility module to expose:

- monotonic now
- monotonic deadline-after-ms / deadline check
- wall-clock now seconds
- optional sleep helper if required

### Pattern 5 — Conservative example modernization

During this migration:

- fix broken example allocator bootstrap only
- defer broader `std.process.Init` / `init.io` modernization unless explicitly chosen later

---

## Concrete repo examples to keep in mind during implementation

## C2 examples

### Simple case
- `src/layout/join.zig`
- local render buffer only
- ideal candidate for direct `append`/`appendSlice`/`print`

### Nested case
- `src/components/menu_bar.zig`
- multiple nested `Managed(u8)` buffers
- still start with direct list methods before reaching for a helper

## C3 examples

### Test/validation case
- `src/terminal/ansi.zig`
- compact and easy place to establish the standard `Writer.fixed` pattern

### High-duplication production case
- `src/terminal/terminal.zig`
- repeated parameter-string builders
- likely best place for one local helper if one is needed

## C4 examples

### Monotonic elapsed-time case
- `src/core/program.zig`

### Monotonic deadline loop case
- `src/terminal/terminal.zig`

### Wall-clock logging case
- `src/core/log.zig`

---

## Risks and tradeoffs

## 1. Over-adopting `std.Io` too quickly

The guide is useful architecturally, but applying it too literally could expand scope unnecessarily.

Examples of scope creep to avoid:

- refactoring working file I/O just to be “more `std.Io`”
- rewriting public APIs to thread `std.Io` everywhere in one migration
- converting every string builder into a writer-based abstraction

## 2. Under-adopting `std.Io`

The opposite risk is treating C3/C4 as trivial symbol-renames and ending up with inconsistent local idioms.

This is especially dangerous for:

- time semantics
- helper signatures involving writers
- fixed-buffer formatting idioms

## 3. Dev-toolchain drift

Both the inventory and the guide assume a Zig 0.16 dev snapshot. Exact symbols may still move.

Mitigation:

- verify time/formatter details against the local stdlib immediately before implementing C4/C5
- keep compatibility helpers narrow so any late symbol churn is easy to absorb

## 4. Ownership mistakes in writer-based helpers

If `std.Io.Writer.Allocating` is introduced at some sites, be careful to:

- pass `*std.Io.Writer`, not writer values by copy
- make ownership transfer explicit (`toOwnedSlice`, `deinit`)

---

## Step-by-step implementation plan

## Phase 0 — lock down the decisions

Before touching source files, confirm these choices:

1. C2 default = direct `Managed(u8)` list methods
2. C3 default = `std.Io.Writer.fixed`
3. C4 = narrow internal time abstraction rather than public API redesign
4. C5 formatter signature = `std.fmt.Options` + `*std.Io.Writer`
5. C1 examples/docs = minimal bootstrap update only

## Phase 1 — core library: dynamic string builders (C2)

Scope:
- layout
- style
- component renderers
- any library/test/example sites blocked by `.writer()` on `Managed(u8)`

Validation loop:

```sh
zig test src/root.zig
```

Goal:
- eliminate the broadest compile blocker with minimal abstraction churn

## Phase 2 — core library: fixed-buffer formatting (C3)

Scope:
- `src/terminal/ansi.zig`
- `src/terminal/terminal.zig`

Validation loop:

```sh
zig test src/root.zig
```

Goal:
- standardize one fixed-buffer formatting idiom
- optionally add one small terminal-local helper if repetition remains noisy

## Phase 3 — core library/tests: formatter convention cleanup (C5)

Scope:
- `src/input/keys.zig`
- `src/input/mouse.zig`
- `tests/input_tests.zig`

Validation loop:

```sh
zig test src/root.zig
zig build test
```

Goal:
- remove a small class of signature drift before tackling the more semantic time work

## Phase 4 — core library: time abstraction and migration (C4)

Scope:
- create one internal compatibility layer
- migrate:
  - `src/core/program.zig`
  - `src/terminal/terminal.zig`
  - `src/core/log.zig`

Validation loop:

```sh
zig test src/root.zig
zig build test
```

Goal:
- restore buildability without committing to a larger `std.Io`-threading refactor

## Phase 5 — examples/docs: allocator bootstrap and residual example fixes (C1 + example-local C2)

Scope:
- all example mains
- `README.md`
- `src/root.zig` docs
- the few example-local C2 sites

Validation loop:

```sh
zig build
```

Goal:
- finish the repo surface cleanly once library/test code is stable

## Phase 6 — final audit

Run:

```sh
zig test src/root.zig
zig build test
zig build
```

Then do a short search-based audit for any remaining known patterns:

```sh
rg -n "GeneralPurposeAllocator|std\.io\.|fixedBufferStream|std\.time\.(Timer|timestamp|milliTimestamp)|std\.fmt\.FormatOptions|\.writer\(\)" src tests examples README.md
```

---

## Open questions / decisions needing confirmation

1. **Example allocator policy**
   - Do we want the minimal current allocator swap, or a broader example modernization to `std.process.Init` later?

2. **C2 helper threshold**
   - Should we start with pure direct list methods everywhere, or allow one local helper in a concentrated rendering subsystem if it clearly improves readability?

3. **C4 implementation backend**
   - What exact current Zig 0.16 time APIs should the internal compatibility layer use on this toolchain?
   - This needs one final local-stdlib verification pass before coding.

4. **C5 formatter style**
   - Confirm that the repo wants the full formatter signature (`fmt` + `Options` + `*Writer`) rather than a simpler two-argument formatter form.

5. **Scope boundary**
   - Confirm that this migration should remain compatibility-focused and should **not** include a repo-wide public API refactor toward explicit `std.Io` threading.

---

## Bottom line

The migration should be treated as:

- **one unrelated mechanical sweep** (C1)
- **two writer-pattern migrations** (C2 and C3)
- **one semantic clock/deadline migration** (C4)
- **one small formatter cleanup** (C5)

If we make the repo-wide decisions once, especially for **dynamic string building**, **fixed-buffer formatting**, and **time semantics**, the actual implementation work should stay disciplined and avoid unnecessary refactors.
