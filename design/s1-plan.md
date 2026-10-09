# S1 implementation plan — live reload + scroll (parallel)

Source: `design.md` (S1 row, "S1 change rules", Render lifecycle, Q3/Q4/Q10). Size: 2 pts (`estimates.md`). Builds on S0 (`s0-skeleton` @ `0480bbc`).

Done = edit the open file in any editor → view updates ≤1s, scrolls to the first changed block (centered) and flashes it; atomic saves work; missing/unreadable/non-UTF-8 → red banner over the last good render, auto-clears on recovery; `make test` green (Swift + JS).

## Shape

```
W1 frozen stubs + shared helper (sequential, small)
 ├─ Q1 LineDiff + tests                         ┐
 ├─ Q2 WatchState reducer + tests, FileWatcher   │ parallel, disjoint files,
 ├─ Q3 js/scroll.js + node test + make target    │ one builder each, own worktree
 └─ Q4 app wiring: Coordinator, banner           ┘
I1 integrate + live checks (sequential)
```

Critical path: W1 → join(Q1–Q4) → I1. Expected longest: Q2 (reducer edge cases) or Q4 (wiring). No duration data.

## Own decisions

- Split the watcher into a pure reducer (`WatchState`, `MarkedCore`, unit-tested) and a thin timer shell (`FileWatcher`, app). The reducer gets the read as an injected closure → tests need no file IO and no `import Foundation` (CLT `_Testing_Foundation` gap, see S0 review)
- Poll = `Timer` every 0.5s on the main run loop; probe = `contentModificationDate` + size via `FileManager.attributesOfItem`. Read when the stamp changes, **or on every poll while a read error is outstanding** (a permission fix does not change mtime or size, so stamp-based skipping applies only after a successful read). Emit text only when it differs from the last emitted text (a `touch` does not re-render)
- Atomic saves: the file can be missing for one poll during write-temp + rename. Banner only after **2 consecutive** missing polls (≤1s). A missing-then-present sequence just re-reads
- Error events emit only when the message changes (no banner flicker on every poll). Retries and message de-duplication are independent: retry every poll, emit only on a new message
- First open read error → banner on an empty page. S0's in-page `**Cannot display:**` text goes away (S0 plan said S1 replaces it)
- Banner (file state) and window subtitle (bridge state, S0) stay separate: different causes, different fixes
- Flash = Web Animations API (`el.animate(...)`, ~1.2s yellow fade). No CSS file change → no conflict with S2/S4 on `base.css`
- Scroll = `scrollIntoView({block: "center", behavior: "smooth"})` (user, 2026-10-09). Flash starts with the scroll
- Scroll-target choice is a pure JS function over parsed `data-sourcepos` ranges → unit-tested with `node --test` (node 22 present). `make test` runs Swift tests, then JS tests if `node` exists
- Resource lookup `subdirectory:` (`cp -R` keeps `Resources/js/`) and the Makefile node step were moved into the S0 baseline (2026-10-09, review), so S1 creates no prerequisite for S3/S5/S6/S8

## Frozen contracts (W1)

```swift
// MarkedCore/LineDiff.swift
public enum LineDiff { public static func firstChangedLine(_ old: String, _ new: String) -> Int? }

// MarkedCore/WatchState.swift
public struct Stamp: Equatable, Sendable { public let mtime: Double; public let size: Int; public init(mtime: Double, size: Int) }
public enum Probe: Equatable, Sendable { case missing, present(Stamp) }
public enum WatchEvent: Equatable, Sendable { case text(String), error(String), cleared }
public struct WatchState {
    public init()
    public mutating func step(_ probe: Probe, read: () -> Result<String, ReadFailure>) -> [WatchEvent]
}
public struct ReadFailure: Error, Equatable { public let message: String; public init(message: String) }
// Public inits are explicit: synthesized memberwise inits are internal, and the app target builds both types

// Marked/FileWatcher.swift (app)
@MainActor final class FileWatcher {
    init(url: URL, interval: TimeInterval = 0.5, onEvent: @escaping (WatchEvent) -> Void)
    func start()   // immediate tick, then every interval
    func stop()
    static func read(_ url: URL) -> Result<String, ReadError>   // unchanged from S0
}

// Marked/SchemeHandler.swift
extension Bundle { func requiredResource(_ name: String, _ ext: String, subdirectory: String? = nil) -> Data }
```

```js
// Resources/js/scroll.js — registers Marked.hook("position", scrollToChange)
// Pure, exported for node: pickTarget(ranges, line) -> index | -1
//   ranges: [{start, end}] in document order (from data-sourcepos "l1:c1-l2:c2")
```

## File ownership

| File | Owner |
|---|---|
| W1 stubs for all files below | W1 (frozen after) |
| `Sources/MarkedCore/LineDiff.swift`, `Tests/MarkedCoreTests/LineDiffTests.swift` | Q1 |
| `Sources/MarkedCore/WatchState.swift`, `Tests/MarkedCoreTests/WatchStateTests.swift`, `Sources/Marked/FileWatcher.swift` | Q2 |
| `Resources/js/scroll.js`, `Tests/js/scroll.test.mjs` | Q3 |
| `Sources/Marked/{WebView,ReaderView}.swift` | Q4 |

## Tasks

### W1 — stubs (sequential, main loop)

- [x] W1.1 Branch `s1-live` from `s0-skeleton`
- [x] W1.2 `Bundle.requiredResource(_:_:subdirectory:)`; `WebView.resource` passes it through (done in S0 baseline)
- [x] W1.3 Stubs compiling with placeholder bodies: `LineDiff.firstChangedLine` → `nil`; `WatchState.step` → `[]`; `FileWatcher` class whose stub `start()` does **one real read** (`Self.read(url)` → `onEvent(.text(s))` or `.error(e.description)`), `stop()` no-op, keep `static read`. This keeps S0 behavior so Q4 can show the fixture before Q2 lands; `Resources/js/scroll.js` registering a no-op `position` hook
- [x] W1.4 `make test` + `make app` green → commit → fork worktrees

### Q1 — LineDiff (builder)

- [x] Q1.1 Tests first (no `import Foundation`): identical → `nil`; change on line 1 → 1; change on line 5 of 10 → 5; append → `old.count + 1`; delete last line → `new.count + 1`; whitespace-only change → its line; `""` → `"a"` → 1; trailing-newline-only change → the line after the last; CRLF vs LF counts as change; **same-style CRLF edit**: `"a\r\nb\r\nc"` → `"a\r\nx\r\nc"` → 2 (Swift treats `\r\n` as one `Character`, so a `Character` split would see one line)
- [x] Q1.2 Implement: split the **UTF-8 bytes** on LF, keeping empties (`text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)`); never split `String`/`Character` on `"\n"` (CRLF is one `Character`). Each line keeps its trailing `\r`, so CRLF vs LF still differ. First differing index + 1, else `min(count) + 1` when counts differ, else `nil`. Reproduced 2026-10-09: `Character` split → 1 line; UTF-8 split → 3 lines, first diff 2

### Q2 — WatchState + FileWatcher (builder)

- [x] Q2.1 Tests first (fake `read` closure counting calls; no `import Foundation`): first `present` → read → `[.text]`; same stamp → no read, `[]`; new stamp, same text → read, `[]`; new stamp, new text → `[.text]`; read failure → `[.error(msg)]`; same failure on next new stamp → `[]`; failure then **same stamp** next poll → read retried (call count +1), still failing → `[]`, then succeeding → `[.cleared, .text]`; after a success, same stamp → no read; recovery → `[.cleared, .text]` (or `[.cleared]` if text unchanged); one `missing` → `[]`; two consecutive `missing` → `[.error("File not found")]`; `missing` then `present` (atomic save) → read, no error; error then `present` → `.cleared`
- [x] Q2.2 Implement `WatchState.step` per the tests and "Own decisions"
- [x] Q2.3 `FileWatcher`: `Timer` (weak self) every `interval`; probe via `FileManager.default.attributesOfItem(atPath:)` → `Stamp(mtime: modificationDate.timeIntervalSince1970, size:)`, any throw → `.missing`; `read` closure maps `ReadError` → `ReadFailure(message: description)`; forward events to `onEvent`. `stop()` invalidates the timer

### Q3 — scroll.js (builder)

- [x] Q3.1 Node test first (`Tests/js/scroll.test.mjs`, `node:test` + `node:assert`): `pickTarget` — line inside one block → it; nested (list in list item) → deepest (last container in document order); line in a gap (blank / deleted) → first block starting after it; past the end → last block; empty ranges → -1; frontmatter range `1:1-4:1` with line 2 → it
- [x] Q3.2 `scroll.js`: parse `data-sourcepos` of `#content [data-sourcepos]`; `changedLine == null` → return (first render, identical); else `pickTarget` → `scrollIntoView({block: "center", behavior: "smooth"})` + `el.animate([{background: "#fff3a0"}, {background: "transparent"}], {duration: 1200})`. Export `pickTarget` for node via `if (typeof module !== "undefined") module.exports = { pickTarget }` (or a `globalThis` guard the test reads); browser path must not throw without `module`
- [x] Q3.3 `Makefile`: `test` runs Swift tests, then `node --test Tests/js` when the dir exists and `node` is found (done in S0 baseline). `make app` already copies `Resources/js/`

### Q4 — wiring (builder)

- [x] Q4.1 `WebView`: append `resource("scroll", "js", subdirectory: "js")` to `userScripts`; `queue.changedLine = LineDiff.firstChangedLine`
- [x] Q4.2 Move read out of `Coordinator.start` (S0 review coupling note): coordinator owns `FileWatcher(url:) { event in … }`: `.text` → `queue.submit`, `.error(m)` → banner `m`, `.cleared` → banner `nil`. `start()` after shell load. No file URL → banner "No file"
- [x] Q4.3 `dismantleNSView(_:coordinator:)` → `coordinator.stop()` → `watcher.stop()` (no timer after window close)
- [x] Q4.4 `ReaderView`: `@State banner: String?`, bound into `WebView`; red bar at top (`.safeAreaInset(edge: .top)`) "⚠ \(msg) — showing the last good version" (or "⚠ \(msg)" when nothing rendered yet). Subtitle logic unchanged
- [x] Q4.5 `make app` builds; launch shows the fixture via the W1 one-shot `FileWatcher` stub (no polling, no scroll yet: Q1–Q3 still placeholders)

### I1 — integrate + checks (sequential, main loop)

- [x] I1.1 Merge Q1–Q4; `make test` (Swift + JS); `make install`
- [x] I1.2 Live checks (2026-10-09, all pass except "close window → watcher stopped": needs GUI scripting, not verified; `dismantleNSView` → `watcher.stop()` is in place) with a temporary env-guarded harness (not committed), fixture `~/tmp/marked fixtures/a b/doc.md`:
  - first open → `scrollY == 0`, no flash
  - append a paragraph at the end with `printf >>` → within 1s content updated; after a further 1s (smooth scroll settles) `scrollY > 0`, target element is the new paragraph
  - atomic save (`write tmp && mv tmp doc.md`) editing line 3 → updated, scrolled near top, no banner at any poll
  - `rm doc.md` → banner within ~1s, last render still shown; restore file → banner cleared, content re-rendered
  - write Latin-1 bytes → banner "file is not UTF-8 text"; restore → cleared
  - `touch doc.md` → no render (token-based or render counter unchanged)
  - close window → watcher stopped (no further reads; log counter)
- [ ] I1.3 code-reviewer loop until clean (max 5); commit on `s1-live`; tick S1 in `design.md`

## Merge conflicts (S1 vs other slices)

- C2 `userScripts`: S1 appends `scroll.js` (one line)
- C4 `ReaderView`: S1 adds the banner inset; S3 adds the find bar
- No merge prerequisite for other slices: the shared resource helper and the node test step are in the S0 baseline

## Resolved questions (user, 2026-10-09)

1. Banner after 2 consecutive missing polls (≤1s grace for atomic saves): keep
2. Scroll: smooth
3. Flash `#fff3a0`, 1.2s: yes
4. `node` as optional dev dependency for JS tests (skipped when absent): yes

No open questions.
