# Zig 0.16 migration inventory for ZigZag

## Environment / Zig version

- Repository: `zigzag`
- Current toolchain tested: `0.16.0-dev.2979+e93834410`
- Repo-declared minimum Zig version: `0.15.0` (`build.zig.zon`)
- Primary build surfaces from `build.zig`:
  - library root: `src/root.zig`
  - explicit test files: `21`
  - examples: `23`

## Method / evidence types

This inventory intentionally distinguishes between different confidence levels:

- **Confirmed by repo build/test failure**: surfaced by `zig build`, `zig build test`, or `zig test src/root.zig`.
- **Confirmed by toolchain probe**: verified with a tiny temporary Zig snippet against the current toolchain.
- **Search-expanded / heuristic**: found by repo-wide search for the same removed API or usage pattern, even if that exact site was not reached before compilation stopped.
- **Stdlib inspection**: current Zig stdlib files were inspected to understand the likely replacement direction.

Because the build stops on first-wave failures, this document goes beyond the first compiler errors and expands each broken API class across the repo.

## Commands used

```sh
zig version
zig build
zig build test
zig test src/root.zig

rg -n "GeneralPurposeAllocator" src tests examples README.md
rg -n "\.writer\(\)" src tests examples
rg -n "std\.io\." src tests examples README.md
rg -n "getWritten\(\)" src tests examples README.md
rg -n "std\.time\.(Timer|timestamp|milliTimestamp|microTimestamp|nanoTimestamp)" src tests examples README.md
rg -n "std\.fmt\.FormatOptions|pub fn format\(" src tests examples README.md
rg -n "std\.array_list\.Managed\(" src tests examples README.md
```

Additional toolchain probes used to confirm pending time breakages not yet reached by repo builds:

```sh
zig test /tmp/check_timestamp.zig   # probes std.time.timestamp()
zig test /tmp/check_milli.zig       # probes std.time.milliTimestamp()
```

Current-stdlib files inspected for likely replacement direction:

- `.../lib/std/std.zig`
- `.../lib/std/heap.zig`
- `.../lib/std/array_list.zig`
- `.../lib/std/fmt.zig`
- `.../lib/std/time.zig`
- `.../lib/std/Io.zig`
- `.../lib/std/Io/Writer.zig`
- `.../lib/std/start.zig`

## Observed build behavior

### `zig build`

- Fails immediately while compiling examples.
- First surfaced class: example allocator bootstrap using `std.heap.GeneralPurposeAllocator`.
- Build summary observed: `0/47 steps succeeded (23 failed)`.

Representative failure:

```text
examples/menu_bar.zig:159:23: error: root source file struct 'heap' has no member named 'GeneralPurposeAllocator'
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
              ~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~
```

### `zig test src/root.zig`

- Good isolating command for the core library surface.
- First surfaced classes: removed array-list writer access and old `std.io` namespace/buffer stream usage.

Representative failures:

```text
src/layout/join.zig:58:26: error: no field or member function named 'writer' in 'array_list.AlignedManaged(u8,null)'
    const writer = result.writer();
                   ~~~~~~^~~~~~~
```

```text
src/terminal/ansi.zig:347:22: error: root source file struct 'std' has no member named 'io'
    var stream = std.io.fixedBufferStream(&buf);
                     ^~
```

### `zig build test`

- Surfaces additional library/test breakages after the first-wave library parse/compile paths.
- Build summary observed: `6/45 steps succeeded (19 failed); 60/60 tests passed` for the subset that compiled.
- Newly surfaced classes: legacy `std.time.Timer` and formatter signature changes.

Representative failures:

```text
src/core/program.zig:55:24: error: root source file struct 'time' has no member named 'Timer'
        clock: std.time.Timer,
               ~~~~~~~~^~~~~~
```

```text
src/input/keys.zig:178:25: error: root source file struct 'fmt' has no member named 'FormatOptions'
        options: std.fmt.FormatOptions,
                 ~~~~~~~^~~~~~~~~~~~~~
```

## Summary table of fix classes

| ID | Fix class | Evidence | Scope | Judgment | Primary surfaces |
|---|---|---|---:|---|---|
| C1 | Example/doc allocator bootstrap: `std.heap.GeneralPurposeAllocator` | Confirmed by `zig build` + exact search | 25 callsites / 25 files | Mechanical | examples, docs |
| C2 | `std.array_list.Managed(...).writer()` removal | Confirmed by `zig test src/root.zig` + `zig build test`; search-expanded | 66 callsites / 41 files | Semi-mechanical | library, tests, examples |
| C3 | `std.io.fixedBufferStream` / `stream.writer()` / `stream.getWritten()` migration to current `std.Io` fixed-buffer writing | Confirmed by `zig test src/root.zig` + exact search | 12 constructor sites (+ paired writer/output retrieval in same blocks) / 2 files | Semi-mechanical | library |
| C4 | Runtime time API migration: `std.time.Timer`, `std.time.timestamp()`, `std.time.milliTimestamp()` | `Timer` confirmed by `zig build test`; `timestamp` + `milliTimestamp` confirmed by toolchain probe + exact search | 16 callsites / 3 files | Requires design judgment | library |
| C5 | Formatter API migration: `std.fmt.FormatOptions` and old custom `format` signature | Confirmed by `zig build test` + exact search | 2 definition sites + 1 direct caller / 3 files | Mechanical | library, tests |

## Detailed fix classes

---

## C1. Example/doc allocator bootstrap: `std.heap.GeneralPurposeAllocator`

### Description

Older example/documentation code uses the classic bootstrap pattern:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

### Why it breaks on current Zig

On the current toolchain, `std.heap` no longer exports `GeneralPurposeAllocator`.
Current stdlib inspection shows `std.heap.DebugAllocator`, `ArenaAllocator`, `SmpAllocator`, etc., but not `GeneralPurposeAllocator`.

### Representative compiler error

```text
examples/menu_bar.zig:159:23: error: root source file struct 'heap' has no member named 'GeneralPurposeAllocator'
```

### Affected files

**Confirmed + exact search (25 callsites / 25 files):**

- `README.md:90`
- `src/root.zig:42`
- `examples/animation.zig:160`
- `examples/charts.zig:313`
- `examples/checkbox_radio.zig:133`
- `examples/clipboard_osc52.zig:188`
- `examples/context_menu.zig:142`
- `examples/counter.zig:113`
- `examples/dashboard.zig:265`
- `examples/dropdown.zig:123`
- `examples/file_browser.zig:169`
- `examples/focus_form.zig:219`
- `examples/form.zig:82`
- `examples/hello_world.zig:328`
- `examples/markdown.zig:93`
- `examples/menu_bar.zig:159`
- `examples/modal.zig:148`
- `examples/showcase.zig:1067`
- `examples/slider.zig:108`
- `examples/tabs.zig:136`
- `examples/text_editor.zig:151`
- `examples/theming.zig:157`
- `examples/toast.zig:150`
- `examples/todo_list.zig:292`
- `examples/tooltip.zig:249`

### Estimated scope

- **Mechanical**
- **Example/doc-only surface** for now
- High repetition: one repeated bootstrap pattern across almost every standalone example main

### Likely replacement strategy

- Pick one modern example allocator bootstrap pattern for Zig 0.16 and apply it consistently across all examples/docs.
- Current-stdlib inspection suggests `std.heap.DebugAllocator(.{})` is the obvious candidate if the goal is to preserve the old “debug-friendly general-purpose allocator” role in examples.
- After the allocator choice is made, this should be a straightforward codemod across all example mains and snippets.

### Open questions

- Should examples/docs use `std.heap.DebugAllocator(.{})`, a different allocator, or mirror whatever `std.start` would use implicitly?
- Should README snippets prioritize pedagogical simplicity over leak-detection/debug behavior?
- Is it worth introducing a tiny shared example helper, or should examples remain totally standalone?

---

## C2. `std.array_list.Managed(...).writer()` removal

### Description

A very common pattern in the library is to build rendered text into `std.array_list.Managed(u8)` buffers and then obtain a writer via:

```zig
var result = std.array_list.Managed(u8).init(allocator);
const writer = result.writer();
```

This is used across component rendering, layout helpers, style rendering, and a few examples/tests.

### Why it breaks on current Zig

Current compiler errors show that `array_list.AlignedManaged(... )` no longer has a `.writer()` member.
Stdlib inspection of `std/array_list.zig` shows:

- `std.array_list.Managed(...)` still exists (deprecated but present),
- it still has helpers like `.print(...)`,
- but the old direct `.writer()` accessor is gone.

Current stdlib also exposes lower-level writer facilities in `std.Io.Writer` / `std.Io.Writer.Allocating`, but those operate with different ownership patterns than the removed convenience method.

### Representative compiler error

```text
src/layout/join.zig:58:26: error: no field or member function named 'writer' in 'array_list.AlignedManaged(u8,null)'
    const writer = result.writer();
                   ~~~~~~^~~~~~~
```

### Affected files / callsites

**Confirmed by build, then search-expanded and manually filtered to likely broken array-list-backed writer sites**

> Note: the raw `.writer()` search found 103 occurrences. This inventory classifies **66** of them as likely broken array-list builder usage, excluding file writers, terminal writers, fixed-buffer stream writers, and one doc string.

#### Library (`36 files / 61 callsites`)

- `src/components/chart.zig:396,419,578`
- `src/components/charting.zig:183`
- `src/components/checkbox.zig:102,379`
- `src/components/confirm.zig:122`
- `src/components/context_menu.zig:292,319`
- `src/components/dropdown.zig:531,628`
- `src/components/file_picker.zig:359`
- `src/components/form.zig:209`
- `src/components/help.zig:121,184`
- `src/components/keybinding.zig:27`
- `src/components/list.zig:463`
- `src/components/markdown.zig:130,266`
- `src/components/menu_bar.zig:394,398,441,493`
- `src/components/modal.zig:401,456,550`
- `src/components/notification.zig:105`
- `src/components/paginator.zig:157,181`
- `src/components/progress.zig:137,194`
- `src/components/radio_group.zig:220`
- `src/components/slider.zig:174`
- `src/components/sparkline.zig:114`
- `src/components/spinner.zig:101`
- `src/components/styled_list.zig:80`
- `src/components/tab_group.zig:766,798,1059`
- `src/components/table.zig:258`
- `src/components/text_area.zig:547`
- `src/components/text_input.zig:381`
- `src/components/timer.zig:201`
- `src/components/toast.zig:196,272`
- `src/components/tooltip.zig:220,286,769`
- `src/components/tree.zig:125`
- `src/components/viewport.zig:273`
- `src/layout/join.zig:58,114`
- `src/layout/place.zig:40,114,199,320`
- `src/style/border.zig:247`
- `src/style/compress.zig:113`
- `src/style/style.zig:565,966,1010`

#### Tests (`1 file / 1 callsite`)

- `tests/input_tests.zig:144` _(also overlaps C5: direct custom formatter call)_

#### Examples (`4 files / 4 callsites`)

- `examples/animation.zig:95`
- `examples/context_menu.zig:93`
- `examples/showcase.zig:515`
- `examples/todo_list.zig:152`

### Estimated scope

- **Semi-mechanical**
- **High-impact**: this is the broadest library-side migration class in the repo
- **66 callsites / 41 files** currently identified

### Likely replacement strategy

Choose one text-builder migration style and apply it consistently:

1. **Minimal-change builder style**
   - replace many `writer.writeAll(...)` / `writer.print(...)` calls with a combination of:
     - `result.appendSlice(...)`
     - `result.append(...)`
     - `result.print(...)`
   - good where the writing logic is simple and local.

2. **Introduce one internal helper for “write into managed byte list”**
   - especially useful because many functions use identical “create byte list -> get writer -> emit strings -> `toOwnedSlice()`” flow.
   - this could hide the ownership ceremony required by modern `std.Io.Writer.Allocating` APIs.

3. **Avoid a repo-wide conversion to unmanaged `std.ArrayList` unless necessary**
   - the repo already uses `std.array_list.Managed(...)` broadly (`192` occurrences across `52` files), and that type still exists on this toolchain.
   - for 0.16 compatibility, a full list-type conversion appears unnecessary unless later migrations force it.

### Duplicates / convergence opportunities

- This class appears in almost every rendering subsystem.
- A single helper or a small local compatibility wrapper could eliminate repeated edits and reduce ownership mistakes.
- Good candidates for commonization:
  - component view builders returning owned `[]const u8`
  - line assembly in layout/style code
  - multi-line boxed rendering in tooltip/modal/menu/dropdown components

### Open questions

- Is the preferred migration style “local `append`/`print` only” or “introduce one helper writer abstraction”?
- If using `std.Io.Writer.Allocating`, what is the cleanest ownership handoff for `std.array_list.Managed(u8)` without rewriting list internals across the repo?
- Should this repo keep `std.array_list.Managed` for now, or opportunistically migrate some hotspots to current `std.ArrayList`/`std.array_list.Aligned` APIs?

---

## C3. `std.io.fixedBufferStream` / `stream.writer()` / `stream.getWritten()` migration

### Description

The terminal/image code builds short parameter strings using the old buffer-stream pattern:

```zig
var stream = std.io.fixedBufferStream(&buf);
const w = stream.writer();
...
const bytes = stream.getWritten();
```

### Why it breaks on current Zig

Two changes converge here:

1. the top-level namespace is now `std.Io` (uppercase `I`), not `std.io`, and
2. `fixedBufferStream` does not exist in the inspected current stdlib.

Current stdlib inspection shows a different fixed-buffer writing style centered on `std.Io.Writer`, e.g. `var w: std.Io.Writer = .fixed(&buf);`, then reading out the written slice from the writer itself.

### Representative compiler error

```text
src/terminal/ansi.zig:347:22: error: root source file struct 'std' has no member named 'io'
    var stream = std.io.fixedBufferStream(&buf);
                     ^~
```

### Affected files / callsites

#### Constructor sites (`std.io.fixedBufferStream`)

- `src/terminal/ansi.zig:347,354,361,368`
- `src/terminal/terminal.zig:611,636,659,689,704,726,751,778`

#### Paired `stream.writer()` uses in the same blocks

- `src/terminal/ansi.zig:348,355,362,369`
- `src/terminal/terminal.zig:612,637,660,690,705,727,752,779`

#### Paired `stream.getWritten()` uses in the same blocks

- `src/terminal/ansi.zig:349,356,363,370`
- `src/terminal/terminal.zig:626,649,679,695,717,736,768,788`

### Estimated scope

- **Semi-mechanical**
- **Narrow file count, high local density**
- `12` constructor sites, all concentrated in `2` files, with corresponding writer/output retrieval changes in the same code blocks

### Likely replacement strategy

- Standardize on one current fixed-buffer writer idiom for Zig 0.16.
- Very likely direction, based on stdlib inspection:
  - create a `std.Io.Writer` fixed to a stack buffer,
  - write through it,
  - use the writer’s buffered slice as the equivalent of old `getWritten()`.
- Because `src/terminal/terminal.zig` repeats the same parameter-building pattern many times, a small local helper could sharply reduce repetition.

### Duplicates / convergence opportunities

- `src/terminal/terminal.zig` repeats the same “build protocol parameter string into fixed buffer” pattern many times.
- A helper such as `formatIntoFixedBuffer(...)` or per-protocol parameter serializers would reduce the number of direct stdlib-touching callsites.

### Open questions

- Which exact current `std.Io.Writer` idiom should be standardized on for fixed buffer writes in this repo?
- Should terminal/image parameter serialization be factored into helpers during migration, or kept as local edits first?

---

## C4. Runtime time API migration: `std.time.Timer`, `std.time.timestamp()`, `std.time.milliTimestamp()`

### Description

The repo still uses several older runtime time APIs from `std.time`:

- `std.time.Timer`
- `std.time.timestamp()`
- `std.time.milliTimestamp()`

These are used for three logically different jobs:

1. **monotonic elapsed-time / frame timing** (`Program`),
2. **real-world timestamps for log prefixes** (`Logger`),
3. **deadline polling loops** in terminal capability detection / clipboard probing.

### Why it breaks on current Zig

Current stdlib inspection shows `std/time.zig` in this toolchain only exposes unit constants and `epoch`; the older runtime clock helpers are not there.

- `std.time.Timer` is already a confirmed repo build failure.
- `std.time.timestamp()` and `std.time.milliTimestamp()` were not reached by the repo build yet, but both were separately confirmed missing via direct toolchain probes.

### Representative errors

#### Repo build failure (`Timer`)

```text
src/core/program.zig:55:24: error: root source file struct 'time' has no member named 'Timer'
        clock: std.time.Timer,
               ~~~~~~~~^~~~~~
```

#### Toolchain probes (`timestamp`, `milliTimestamp`)

```text
/tmp/check_timestamp.zig:3:17: error: root source file struct 'time' has no member named 'timestamp'
    _ = std.time.timestamp();
        ~~~~~~~~^~~~~~~~~~
```

```text
/tmp/check_milli.zig:3:17: error: root source file struct 'time' has no member named 'milliTimestamp'
    _ = std.time.milliTimestamp();
        ~~~~~~~~^~~~~~~~~~~~~~~
```

### Affected files / callsites

#### `std.time.Timer` (confirmed by repo build)

- `src/core/program.zig:55,79,790`

#### `std.time.timestamp()` (search-discovered, confirmed by toolchain probe)

- `src/core/log.zig:35`

#### `std.time.milliTimestamp()` (search-discovered, confirmed by toolchain probe)

- `src/terminal/terminal.zig:548,549,1376,1378,1430,1432,1470,1472,1531,1533,1613,1615`

### Estimated scope

- **Requires design judgment**
- `16` callsites across `3` files
- Small file count, but behaviorally important because the replacements need the right time semantics

### Likely replacement strategy

Treat this as **one time-abstraction decision**, with three sub-mappings:

1. **Program frame/elapsed timing**
   - replace `std.time.Timer` with the current monotonic/elapsed-time approach available on Zig 0.16.
   - likely replacement surface is in modern `std.Io` time/clock APIs rather than old `std.time` helpers.

2. **Logger timestamps**
   - replace `std.time.timestamp()` with a current real-time clock source.
   - keep human-readable `[HH:MM:SS]` formatting behavior.

3. **Terminal deadline polling**
   - replace `std.time.milliTimestamp()` loops with a current monotonic deadline strategy.
   - these should almost certainly remain monotonic/deadline-based rather than wall-clock based.

A small internal compatibility wrapper or `time_compat.zig`-style helper would likely pay off here.

### Duplicates / convergence opportunities

- All remaining runtime time decisions are concentrated in only `3` files.
- A single internal time utility layer could avoid leaking modern clock API details everywhere.
- The terminal deadline loops are structurally repetitive and can likely share one helper once the replacement API is chosen.

### Open questions

- What exact modern clock/time API should this repo standardize on for Zig `0.16.0-dev`?
- For terminal timeouts, should the chosen clock include or exclude suspend time?
- Do we want a single repo-local abstraction for “now”, “deadline after N ms”, and “elapsed since start” before patching callsites?

---

## C5. Formatter API migration: `std.fmt.FormatOptions` and old custom `format` signature

### Description

Two custom formatter methods still use the older formatter signature shape:

```zig
pub fn format(
    self: T,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void
```

### Why it breaks on current Zig

Current stdlib inspection shows `std.fmt.Options`, not `std.fmt.FormatOptions`.
Current formatter examples in stdlib also use `*std.Io.Writer` rather than `anytype` writers for standard formatting hooks.

### Representative compiler error

```text
src/input/keys.zig:178:25: error: root source file struct 'fmt' has no member named 'FormatOptions'
        options: std.fmt.FormatOptions,
                 ~~~~~~~^~~~~~~~~~~~~~
```

### Affected files / callsites

#### Formatter definitions

- `src/input/keys.zig:175,178`
- `src/input/mouse.zig:39,42`

#### Direct in-repo caller using the old explicit signature

- `tests/input_tests.zig:144` _(also overlaps C2 because it passes `buf.writer()`)_

### Estimated scope

- **Mechanical**
- Small surface: `2` definition sites + `1` direct test caller

### Likely replacement strategy

Because both current implementations ignore `fmt` and options:

- either adopt the modern full formatter signature (`std.fmt.Options` + `*std.Io.Writer`), or
- if appropriate for current Zig formatting hooks, adopt the simpler current-style `format(self, writer: *std.Io.Writer)` form.

The right choice depends on which of the current stdlib-supported formatter shapes best integrates with how the repo formats these types.

### Open questions

- Is the simpler two-argument `format(self, writer)` form sufficient for `KeyEvent` / `MouseEvent`, or should these remain fully specifier-compatible?
- After changing the signature, should the direct test call switch to `writer.print(...)`-style usage instead of manually invoking `format(...)`?

## Duplicates and convergence opportunities

1. **One allocator bootstrap repeated everywhere in examples/docs**
   - C1 is almost a pure codemod once the preferred allocator is chosen.

2. **One managed-byte-list writer pattern repeated throughout rendering code**
   - C2 is the biggest convergence opportunity.
   - A small helper or compatibility wrapper could drastically reduce repeated edits and ownership mistakes.

3. **One fixed-buffer parameter-building pattern repeated in terminal protocol code**
   - C3 is concentrated enough that a helper should be strongly considered.

4. **One repo-local time abstraction could absorb all remaining `std.time` migration choices**
   - C4 affects only 3 files but involves semantics, not just syntax.

5. **Avoid unnecessary scope expansion**
   - `std.array_list.Managed(` appears `192` times across `52` files, but it is **not currently a compile blocker** on this toolchain.
   - The migration should avoid accidentally turning C2 into a full list-type refactor unless later fixes require it.

## Build-surface breakdown

### Library

Primary migration classes affecting the core library:

- **C2** `std.array_list.Managed(...).writer()` removal
- **C3** `std.io.fixedBufferStream` / fixed-buffer writer migration
- **C4** runtime time API migration
- **C5** formatter signature migration

The best library-focused feedback loop is:

```sh
zig test src/root.zig
```

That command already isolates the core library and surfaced C2 + C3 immediately.
After those are addressed, it should expose the next layer more clearly.

### Tests

No large test-only migration class was found.
The tests mostly inherit library breakages.
The one direct test-surface overlap identified so far is:

- `tests/input_tests.zig:144` (overlaps C2 and C5)

The test-focused validation loop after library fixes is:

```sh
zig build test
```

### Examples

Immediate example blocker:

- **C1** across `23` example mains

Additional likely example-local migration work after C1 is fixed:

- **C2** in:
  - `examples/animation.zig:95`
  - `examples/context_menu.zig:93`
  - `examples/showcase.zig:515`
  - `examples/todo_list.zig:152`

The example validation loop is:

```sh
zig build
```

### Docs / README snippets

Currently identified doc-surface breakages:

- `README.md:90` (C1)
- `src/root.zig:42` doc example (C1)

These are not build blockers, but they should be updated after the code migration so published examples match the repo.

## Recommended migration order

### 1. Decide the reusable migration patterns first

Before patching callsites, settle these repo-wide decisions:

- C2: managed byte-list writing strategy
- C3: fixed-buffer writer strategy
- C4: modern time abstraction / clock choices

These choices affect many files and are worth reasoning through once.

### 2. Patch the core library first

Recommended order inside the library:

1. **C2** — array-list writer removal
2. **C3** — fixed-buffer `std.Io` migration
3. **C4** — runtime time APIs
4. **C5** — formatter signature update

Suggested validation loop during this phase:

```sh
zig test src/root.zig
```

Why this order:

- C2 and C3 currently block the broadest library compile surface.
- C4 is semantically important and should be handled once the text-writer churn settles.
- C5 is small and can be cleaned up after the larger API migrations.

### 3. Patch test overlaps

Once the library compiles further, clean up direct test-side overlaps and re-run:

```sh
zig build test
```

Main known direct test overlap today:

- `tests/input_tests.zig:144`

### 4. Patch examples and docs last

After the library/test surfaces are stable:

1. **C1** across all example mains + README/root docs
2. Remaining example-local C2 callsites
3. Re-run:

```sh
zig build
```

### Practical note

If you want one quick morale-boosting/mechanical change early, C1 is easy to batch-edit at any time. But from a dependency standpoint, it should not distract from the core-library-first migration path.

## Risks / unknowns

- This toolchain is a **0.16-dev** build; final 0.16 may still shift APIs.
- More migration classes may appear after current first-wave blockers are removed.
- C4 has behavioral risk: choosing the wrong modern clock semantics could subtly change animation timing, timeouts, or log timestamp behavior.
- C2 has ownership/lifetime risk if the migration uses low-level `std.Io.Writer.Allocating` primitives without a consistent helper.
- The repo’s broad `std.array_list.Managed` usage is not a blocker today, but careless migration choices could accidentally balloon scope.

## Appendix: raw search patterns and counts

### Exact-symbol searches

- `GeneralPurposeAllocator`
  - `25` callsites / `25` files
- `std.io.`
  - `12` callsites / `2` files
- `getWritten()`
  - `12` callsites / `2` files
- `std.time.(Timer|timestamp|milliTimestamp|microTimestamp|nanoTimestamp)`
  - `16` callsites / `3` files
- `std.fmt.FormatOptions`
  - `2` definition sites / `2` files

### `.writer()` search and heuristic reduction

- Raw search: `.writer()`
  - `103` occurrences total
- After excluding clearly unrelated writer sources (`self.file.writer()`, terminal writers, `self.writer()`, fixed-buffer `stream.writer()`, and one doc string), likely broken array-list-backed writer sites:
  - `66` callsites / `41` files

### Broader background signal (not a blocking class by itself)

- `std.array_list.Managed(`
  - `192` occurrences / `52` files
  - included here because it strongly influences the safest C2 migration strategy, even though it is not itself a current compile error

### Toolchain probes run

- `std.time.timestamp()` probe: **missing** on current toolchain
- `std.time.milliTimestamp()` probe: **missing** on current toolchain

---

This document is intentionally an inventory, not a patch plan implementation. The next useful step is to reason through the replacement strategy for C2, C3, and C4 once, then apply those choices systematically.
