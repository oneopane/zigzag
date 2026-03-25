# Zig 0.16 implementation plan for ZigZag

## Purpose and how to use this document

This is the **execution document** for the Zig 0.16 migration.

Use it while patching files, not while deciding the overall strategy. It assumes the high-level reasoning is already captured elsewhere and focuses on:

- what order to work in
- which file groups to touch together
- what is mechanical vs review-heavy
- which validation commands to run after each batch
- what boundaries we should not cross during this migration

This document is intended to be used alongside the existing migration analysis, not instead of it.

---

## Relationship to the source documents

### `zig-std-io-guide.md`

Role: **reference for the modern Zig 0.16 `std.Io` mental model**.

Use it when implementing classes that are directly or indirectly shaped by the `std.Io` redesign, especially:

- modern fixed-buffer formatting (`std.Io.Writer.fixed`)
- modern owned dynamic output (`std.Io.Writer.Allocating`)
- writer helper conventions (`*std.Io.Writer`)
- time / clocks / deadlines as part of the `std.Io` world

For this migration, treat it as the **architectural guide**, not the patch checklist.

### `docs/zig-0.16-migration-inventory.md`

Role: **canonical inventory of what is broken and where**.

Use it for:

- exact affected files/callsites
- evidence level (build failure vs search-expanded)
- rough scope and risk per fix class

During implementation, this is the document to consult when building a patch list for each class.

### `docs/zig-0.16-migration-plan.md`

Role: **design-aware migration strategy**.

Use it for:

- the classification of C1–C5
- the repo-level pattern choices already made
- examples of preferred migration shapes
- why certain tempting refactors should be avoided

This document inherits the assumptions from that plan and turns them into concrete work phases.

---

## Assumptions locked in for implementation

These are the working assumptions for the migration unless explicitly revisited.

1. **Compatibility-focused scope**
   - The goal is to make ZigZag build and test on the current Zig 0.16-dev toolchain.
   - This is **not** a broader repo redesign.

2. **No repo-wide public API refactor toward explicit `std.Io` threading**
   - Even though the guide points in that direction conceptually, we are not adopting that as migration scope unless required.

3. **Keep `std.array_list.Managed(...)` for now**
   - It is not itself a compile blocker.
   - We are fixing broken writer access, not redesigning the repo’s container choices.

4. **Prefer local, narrow fixes over broad abstraction changes**
   - Introduce helpers only where they remove clear repetition in a concentrated subsystem.

5. **Time migration gets one internal compatibility layer**
   - We will not patch `std.time.*` callsites ad hoc with mismatched semantics.

---

## Migration principles / scope boundaries

## In scope

- Restore compatibility for the known migration classes C1–C5.
- Standardize a few repo-local implementation patterns where Zig 0.16 requires it.
- Keep changes localized to the currently broken surfaces.

## Out of scope unless forced by compile blockers

- Refactoring examples to `main(init: std.process.Init)` across the board.
- Refactoring the library to thread `io: std.Io` through all public APIs.
- Replacing all `std.array_list.Managed(...)` usage with newer list APIs.
- Converting every local string builder into a generic writer abstraction.
- Larger terminal/runtime redesign beyond what is needed for current breakages.

## “Do not refactor yet” boundaries

- Do not change component APIs just to make them look more modern.
- Do not unify wall-clock time and monotonic time behind one vague helper.
- Do not create repo-wide helpers for C2 or C3 until a local subsystem proves they reduce repetition.
- Do not mix example bootstrap modernization with library compatibility work.

---

## Fix classes and execution posture

| Class | Short name | Execution posture | Notes |
|---|---|---|---|
| C1 | example/doc allocator bootstrap | **Mechanical** | Narrow sweep; defer broader entrypoint modernization |
| C2 | `Managed(...).writer()` removal | **Semi-mechanical + review** | Largest surface; use preferred default pattern |
| C3 | fixed-buffer stream migration | **Semi-mechanical + review** | Directly `std.Io`-driven; localized to terminal code |
| C4 | time / clock / deadline migration | **Design-sensitive** | Centralize via repo-local compatibility layer |
| C5 | formatter signature drift | **Mechanical after convention choice** | Small surface; use modern writer convention |

---

## Current progress snapshot

Snapshot date: 2026-03-25

Completed so far on this branch:
- added the migration reference docs:
  - `docs/zig-0.16-migration-inventory.md`
  - `docs/zig-0.16-migration-plan.md`
  - `docs/zig-0.16-implementation-plan.md`
  - `zig-std-io-guide.md`
- completed the first C2 batch (Phase 1A / Group A):
  - `src/layout/join.zig`
  - `src/layout/place.zig`
  - `src/style/border.zig`
  - `src/style/compress.zig`
  - `src/style/style.zig`
- completed the C3 fixed-buffer writer migration in:
  - `src/terminal/ansi.zig`
  - `src/terminal/terminal.zig`
- completed the second C2 batch (Phase 1B / Group B):
  - `src/components/checkbox.zig`
  - `src/components/confirm.zig`
  - `src/components/help.zig`
  - `src/components/keybinding.zig`
  - `src/components/notification.zig`
  - `src/components/paginator.zig`
  - `src/components/progress.zig`
  - `src/components/radio_group.zig`
  - `src/components/slider.zig`
  - `src/components/spinner.zig`
  - `src/components/styled_list.zig`
  - `src/components/timer.zig`
  - `src/components/tree.zig`
  - `src/components/viewport.zig`
- completed the third C2 batch (Phase 1C / Group C):
  - `src/components/charting.zig`
  - `src/components/file_picker.zig`
  - `src/components/list.zig`
  - `src/components/markdown.zig`
  - `src/components/sparkline.zig`
  - `src/components/table.zig`
  - `src/components/text_input.zig`
  - `src/components/toast.zig`
- completed the fourth C2 batch (Phase 1D / Group D):
  - `src/components/chart.zig`
  - `src/components/context_menu.zig`
  - `src/components/dropdown.zig`
  - `src/components/form.zig`
  - `src/components/menu_bar.zig`
  - `src/components/modal.zig`
  - `src/components/tab_group.zig`
  - `src/components/text_area.zig`
  - `src/components/tooltip.zig`

Validation snapshot:
- `zig version` → `0.16.0-dev.2979+e93834410`
- `zig test src/root.zig` → passes
- `zig build test` → still fails, but the renderer frontier is now clear and the remaining failures are:
  - C4 time migration in `src/core/program.zig` (`std.time.Timer`)
  - C5 formatter migration in `src/input/keys.zig` (`std.fmt.FormatOptions`), with `src/input/mouse.zig` still tracked in the migration plan

Immediate next step:
- return to C5 and C4 now that Phase 1 / C2 renderer migration is complete

---

## Recommended phase order

### Phase 0 — preflight and execution setup

Goal:
- start from a clean compatibility-focused plan
- avoid mixing unrelated work

Actions:
- keep these three docs open while working:
  - `zig-std-io-guide.md`
  - `docs/zig-0.16-migration-inventory.md`
  - `docs/zig-0.16-migration-plan.md`
- treat this file as the session checklist
- keep work batched by phase and subsystem

Validation baseline:

```sh
zig version
zig test src/root.zig
zig build test
zig build
```

Expected outcome:
- current failures are understood and consistent with the inventory

---

### Phase 1 — C2 library sweep: replace broken `Managed(...).writer()` usage

Goal:
- remove the broadest compile blocker in the core library
- standardize one default string-building idiom for the repo

Default pattern to use:
- `Managed(u8)` stays
- replace `.writer()`-based local building with:
  - `append`
  - `appendSlice`
  - `print`
  - `toOwnedSlice`

### Phase 1A — layout and style first

Likely touch points:
- `src/layout/join.zig`
- `src/layout/place.zig`
- `src/style/border.zig`
- `src/style/compress.zig`
- `src/style/style.zig`

Why first:
- these are foundational helpers and already surfaced by `zig test src/root.zig`
- they set the local idiom for the rest of the renderers

Validation after 1A:

```sh
zig test src/root.zig
```

Success condition:
- no new syntax/type errors in these files
- error output moves deeper into remaining C2 sites rather than circling back

### Phase 1B — simpler component renderers

Likely touch points:
- `src/components/confirm.zig`
- `src/components/help.zig`
- `src/components/keybinding.zig`
- `src/components/notification.zig`
- `src/components/paginator.zig`
- `src/components/progress.zig`
- `src/components/radio_group.zig`
- `src/components/slider.zig`
- `src/components/spinner.zig`
- `src/components/styled_list.zig`
- `src/components/timer.zig`
- `src/components/tree.zig`
- `src/components/viewport.zig`
- `src/components/checkbox.zig`

Why this grouping:
- these tend to have local one-buffer or few-buffer assembly patterns
- they are lower-risk places to apply the chosen default before touching the more nested renderers

Validation after 1B:

```sh
zig test src/root.zig
```

### Phase 1C — medium complexity renderers

Likely touch points:
- `src/components/file_picker.zig`
- `src/components/list.zig`
- `src/components/markdown.zig`
- `src/components/sparkline.zig`
- `src/components/table.zig`
- `src/components/text_input.zig`
- `src/components/toast.zig`
- `src/components/charting.zig`

Validation after 1C:

```sh
zig test src/root.zig
```

### Phase 1D — high-complexity / nested-builder renderers

Likely touch points:
- `src/components/chart.zig`
- `src/components/context_menu.zig`
- `src/components/dropdown.zig`
- `src/components/form.zig`
- `src/components/menu_bar.zig`
- `src/components/modal.zig`
- `src/components/tab_group.zig`
- `src/components/text_area.zig`
- `src/components/tooltip.zig`

Execution note:
- start with direct list methods even here
- only introduce a local helper if the same writer-oriented shape repeats enough inside one subsystem to justify it

Validation after 1D:

```sh
zig test src/root.zig
```

Exit criterion for Phase 1:
- all library-side C2 `.writer()` breakages are resolved
- if any `.writer()` remain in the repo, they are either:
  - non-broken file/terminal writers
  - fixed-buffer writer sites belonging to C3
  - remaining example/test cleanup that is intentionally deferred

---

### Phase 2 — C3 terminal fixed-buffer formatting sweep

Goal:
- replace old `std.io.fixedBufferStream` usage with the modern fixed-buffer writer pattern
- keep any helper local to terminal/image code

Default pattern to use:
- `var w: std.Io.Writer = .fixed(&buf)`
- `w.print(...)`
- `w.buffered()`

Likely touch points:
- `src/terminal/ansi.zig`
- `src/terminal/terminal.zig`

Suggested internal batching:

#### Phase 2A — establish pattern in tests / small functions
- `src/terminal/ansi.zig`

Why first:
- compact, easy to reason about
- good place to confirm the `Writer.fixed` pattern before applying it repeatedly in `terminal.zig`

Validation after 2A:

```sh
zig test src/root.zig
```

#### Phase 2B — apply pattern across terminal protocol builders
- `src/terminal/terminal.zig`

Possible local helper candidates:
- parameter-string builder for Kitty/iTerm2 protocol payloads
- helper should stay local to `src/terminal/terminal.zig` or `src/terminal/`

Validation after 2B:

```sh
zig test src/root.zig
```

Exit criterion for Phase 2:
- no remaining `std.io.fixedBufferStream` / `stream.writer()` / `stream.getWritten()` sites in library code
- fixed-buffer formatting sites follow one consistent idiom

---

### Phase 3 — C5 formatter convention cleanup

Goal:
- align custom formatters with current Zig formatter conventions
- remove small writer-signature drift before the time work

Default convention to use:

```zig
pub fn format(
    self: T,
    comptime fmt: []const u8,
    options: std.fmt.Options,
    writer: *std.Io.Writer,
) !void
```

Likely touch points:
- `src/input/keys.zig`
- `src/input/mouse.zig`
- `tests/input_tests.zig`

Execution note:
- keep rendering behavior the same
- update tests so they use current formatting/writer behavior rather than preserving the old direct-call convention if it obscures the new API shape

Validation after Phase 3:

```sh
zig test src/root.zig
zig build test
```

Exit criterion:
- no remaining `std.fmt.FormatOptions` usage
- formatter-related tests compile under the chosen convention

---

### Phase 4 — C4 time migration via repo-local compatibility layer

Goal:
- migrate time-sensitive code without smearing new clock semantics ad hoc across the repo

Required design posture:
- separate three semantics explicitly:
  1. monotonic elapsed time
  2. monotonic deadlines
  3. wall-clock time

Likely touch points:
- `src/core/program.zig`
- `src/core/log.zig`
- `src/terminal/terminal.zig`
- one new internal helper module/file for time compatibility

Execution order inside Phase 4:

#### Phase 4A — implement the repo-local time helper
Responsibilities:
- provide monotonic “now” for elapsed-time bookkeeping
- provide monotonic deadline construction/checking
- provide wall-clock seconds for logger timestamps
- optionally provide sleep helper if needed by migrated code

Validation after 4A:
- helper compiles cleanly in the local toolchain

#### Phase 4B — migrate `src/core/program.zig`
Use the monotonic elapsed-time side of the helper.

Validation after 4B:

```sh
zig test src/root.zig
```

#### Phase 4C — migrate terminal deadline loops in `src/terminal/terminal.zig`
Use the monotonic deadline side of the helper.

Validation after 4C:

```sh
zig test src/root.zig
```

#### Phase 4D — migrate logger timestamping in `src/core/log.zig`
Use the wall-clock side of the helper.

Validation after 4D:

```sh
zig test src/root.zig
zig build test
```

Exit criterion for Phase 4:
- no remaining uses of:
  - `std.time.Timer`
  - `std.time.timestamp()`
  - `std.time.milliTimestamp()`
- monotonic vs wall-clock semantics remain clearly separated

---

### Phase 5 — C1 example/doc bootstrap sweep + residual example-local C2 cleanup

Goal:
- finish examples/docs only after the library and tests are stable

Likely touch points:
- `README.md`
- `src/root.zig` doc snippet
- allocator bootstrap in `23` example mains
- example-local C2 sites:
  - `examples/animation.zig`
  - `examples/context_menu.zig`
  - `examples/showcase.zig`
  - `examples/todo_list.zig`

Execution order inside Phase 5:

#### Phase 5A — allocator bootstrap sweep (C1)
- apply one chosen allocator bootstrap pattern consistently
- keep example structure intact
- do not modernize all examples to `main(init: std.process.Init)` as part of this phase

#### Phase 5B — residual example-local string-builder fixes
- apply the same C2 default pattern used in library code

Validation after Phase 5:

```sh
zig build
```

Exit criterion:
- examples compile under the chosen bootstrap pattern
- README/root docs match the current example bootstrap convention

---

### Phase 6 — final audit and cleanup pass

Goal:
- verify the migration is complete and no known classes remain

Validation commands:

```sh
zig test src/root.zig
zig build test
zig build
```

Search audit:

```sh
rg -n "GeneralPurposeAllocator|std\.io\.|fixedBufferStream|std\.time\.(Timer|timestamp|milliTimestamp)|std\.fmt\.FormatOptions|\.writer\(\)" src tests examples README.md
```

Interpretation of audit results:
- `GeneralPurposeAllocator` should be gone from repo code/docs
- `std.io.` / `fixedBufferStream` should be gone from migrated code
- `std.time.Timer` / `timestamp` / `milliTimestamp` should be gone
- `std.fmt.FormatOptions` should be gone
- remaining `.writer()` uses should be reviewed and should only be valid modern writer sites

---

## Per-class execution checklists

## C1 checklist — example/doc allocator bootstrap

Type: **mechanical**

- [ ] Choose the allocator bootstrap pattern to use for examples/docs
- [ ] Update all example mains listed in the inventory
- [ ] Update `README.md`
- [ ] Update `src/root.zig` doc snippet
- [ ] Confirm no broader example-entry refactor was introduced accidentally
- [ ] Run `zig build`
- [ ] Search for leftover `GeneralPurposeAllocator`

## C2 checklist — `Managed(...).writer()` removal

Type: **semi-mechanical with review**

- [x] Use direct `Managed(u8)` list methods by default
- [x] Convert foundational layout/style files first
- [x] Convert simple component renderers next
- [x] Convert medium-complexity renderers
- [x] Convert high-complexity nested renderers last
- [x] Keep helper use narrow; current helpers remain local (`ListWriter` in `src/style/style.zig`, plus direct list recursion in `src/components/tree.zig`)
- [x] Avoid changing container types unless forced
- [x] Re-run `zig test src/root.zig` after the current foundational/simple-component batches
- [x] Search for leftover broken `Managed(...).writer()` sites to define the next batches

## C3 checklist — fixed-buffer stream migration

Type: **semi-mechanical with review**

- [x] Establish the standard `std.Io.Writer.fixed` pattern in `src/terminal/ansi.zig`
- [x] Apply the same pattern across `src/terminal/terminal.zig`
- [x] No helper was needed; the pattern stayed local to terminal/image code
- [x] Ensure output retrieval uses the writer’s buffered contents
- [x] Re-run `zig test src/root.zig`
- [x] Search for leftover `std.io.fixedBufferStream`, `stream.writer()`, and `stream.getWritten()` sites

## C4 checklist — time / clock / deadline migration

Type: **design-sensitive**

- [ ] Confirm the exact modern time APIs to use against the local toolchain
- [ ] Create one narrow internal compatibility layer
- [ ] Implement monotonic elapsed-time helper(s)
- [ ] Implement monotonic deadline helper(s)
- [ ] Implement wall-clock timestamp helper(s)
- [ ] Migrate `src/core/program.zig`
- [ ] Migrate `src/terminal/terminal.zig`
- [ ] Migrate `src/core/log.zig`
- [ ] Verify monotonic and wall-clock paths were not mixed
- [ ] Re-run `zig test src/root.zig` and `zig build test`
- [ ] Search for leftover old `std.time` runtime APIs

## C5 checklist — formatter convention cleanup

Type: **mechanical after convention choice**

- [ ] Confirm the formatter signature convention to use
- [ ] Update `src/input/keys.zig`
- [ ] Update `src/input/mouse.zig`
- [ ] Update `tests/input_tests.zig`
- [ ] Confirm tests exercise formatting in a current-style way
- [ ] Re-run `zig build test`
- [ ] Search for leftover `std.fmt.FormatOptions`

---

## File groupings / likely touch points

These groupings are intended to support session-by-session work.

## Group A — foundational rendering helpers

- `src/layout/join.zig`
- `src/layout/place.zig`
- `src/style/border.zig`
- `src/style/compress.zig`
- `src/style/style.zig`

Used for:
- early C2 work
- establishing the default local string-building idiom

## Group B — simple component renderers

- `src/components/confirm.zig`
- `src/components/help.zig`
- `src/components/keybinding.zig`
- `src/components/notification.zig`
- `src/components/paginator.zig`
- `src/components/progress.zig`
- `src/components/radio_group.zig`
- `src/components/slider.zig`
- `src/components/spinner.zig`
- `src/components/styled_list.zig`
- `src/components/timer.zig`
- `src/components/tree.zig`
- `src/components/viewport.zig`
- `src/components/checkbox.zig`

Used for:
- low-risk C2 batching

## Group C — medium-complexity renderers

- `src/components/file_picker.zig`
- `src/components/list.zig`
- `src/components/markdown.zig`
- `src/components/sparkline.zig`
- `src/components/table.zig`
- `src/components/text_input.zig`
- `src/components/toast.zig`
- `src/components/charting.zig`

Used for:
- mid-phase C2 batching

## Group D — nested/high-complexity renderers

- `src/components/chart.zig`
- `src/components/context_menu.zig`
- `src/components/dropdown.zig`
- `src/components/form.zig`
- `src/components/menu_bar.zig`
- `src/components/modal.zig`
- `src/components/tab_group.zig`
- `src/components/text_area.zig`
- `src/components/tooltip.zig`

Used for:
- late C2 work requiring more deliberate review

## Group E — terminal / protocol formatting

- `src/terminal/ansi.zig`
- `src/terminal/terminal.zig`

Used for:
- all C3 work
- part of C4 deadline-loop migration

## Group F — input / formatter conventions

- `src/input/keys.zig`
- `src/input/mouse.zig`
- `tests/input_tests.zig`

Used for:
- all C5 work

## Group G — time-sensitive runtime code

- `src/core/program.zig`
- `src/core/log.zig`
- `src/terminal/terminal.zig`
- one new internal time helper module

Used for:
- all C4 work

## Group H — examples/docs

- `README.md`
- `src/root.zig`
- all example mains with allocator bootstrap usage
- example-local C2 sites:
  - `examples/animation.zig`
  - `examples/context_menu.zig`
  - `examples/showcase.zig`
  - `examples/todo_list.zig`

Used for:
- C1 and deferred example cleanup

---

## Validation strategy and commands

## Fast validation loop during library work

Use after every meaningful batch:

```sh
zig test src/root.zig
```

Notes:
- during earlier phases, this may still fail overall due to remaining later-phase breakages
- the success signal is that already-fixed files do not reappear with new errors and the failure frontier moves forward predictably

## Mid-stage validation

Use after C5 and during/after C4:

```sh
zig build test
```

Notes:
- catches test-surface issues not exercised by the library root alone

## Full-surface validation

Use after examples/docs work and at the end:

```sh
zig build
```

## Search-based audit

Run after each phase when relevant:

```sh
rg -n "GeneralPurposeAllocator|std\.io\.|fixedBufferStream|std\.time\.(Timer|timestamp|milliTimestamp)|std\.fmt\.FormatOptions|\.writer\(\)" src tests examples README.md
```

Use the results to confirm that:
- a finished class is actually drained
- remaining hits belong only to expected later phases or valid modern code

---

## Risks / rollback guidance

## Main execution risks

1. **C2 accidental scope expansion**
   - Risk: turning a writer-method removal into a repo-wide container or abstraction rewrite
   - Mitigation: stick to direct list methods by default

2. **C3 abstraction creep**
   - Risk: inventing a repo-wide fixed-buffer helper when only terminal code needs it
   - Mitigation: keep helpers local to terminal/image code if used at all

3. **C4 semantic regressions**
   - Risk: mixing monotonic and wall-clock time, or changing timeout behavior subtly
   - Mitigation: use one explicit internal time layer and migrate by semantics, not by symbol name alone

4. **Example churn distracting from library progress**
   - Risk: spending time on example entrypoint modernization while the core library still fails
   - Mitigation: keep C1 to the end and keep it narrow

## Rollback guidance

- Keep changes phase-scoped.
- If a phase becomes noisy, roll back that phase’s helper/abstraction change before rolling back unrelated file edits.
- Prefer reverting a local helper introduction over reverting an entire batch if the helper caused most of the churn.
- If a batch regresses behavior or readability badly, split the batch into smaller subsystem chunks instead of pressing forward.

---

## Open questions / assumptions needing confirmation before coding

1. **Exact example allocator bootstrap choice**
   - This plan assumes one minimal current allocator pattern will be chosen and applied uniformly.

2. **Final formatter signature shape**
   - This plan assumes the full `fmt + std.fmt.Options + *std.Io.Writer` form unless local toolchain verification suggests a better current convention.

3. **Exact local-toolchain time API details for the compatibility layer**
   - This remains the one place where a final local stdlib verification pass is required before implementation.

4. **Helper threshold for C2/C3**
   - This plan assumes helpers remain optional and local, not mandatory or repo-wide.

5. **Compatibility-focused scope remains in force**
   - If implementation reveals a broader API refactor is required, pause and update the plan rather than letting the scope drift implicitly.

---

## Day-to-day usage summary

For each migration session:

1. Pick one phase and one file group.
2. Re-read the relevant class section in:
   - `docs/zig-0.16-migration-inventory.md`
   - `docs/zig-0.16-migration-plan.md`
3. Apply only the pattern already chosen for that class.
4. Run the phase’s validation command.
5. Confirm the failure frontier moved forward and no finished class reappeared.
6. Only then move to the next batch.

If used this way, this document should function as the practical checklist for completing the migration without unnecessary redesign churn.
