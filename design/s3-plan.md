# S3 implementation plan — find (parallel)

Source: `design.md` (S3 row, "Find skips mermaid", "Find must match across inline element boundaries", soft breaks), `grill.md` Q6. Size: 2 pts (`estimates.md`). Builds on `s2-styles` @ `960d000`.

Done = Cmd-F or Ctrl-F opens a find bar in the current window; typing highlights every match and shows "n of m"; Enter / Cmd-G go to the next match, Shift-Enter / Shift-Cmd-G to the previous, wrapping at the ends, with the current match scrolled into view; Esc closes the bar and clears the highlights; a live reload keeps the highlights and updates the count; matches work across bold/italic/link boundaries and across wrapped lines; `make test` green; live check passes.

## Shape

```
W3 frozen stubs + CSS + spike (sequential)
 ├─ K1 js/find.js: pure matcher + DOM highlight + hook + node tests   ┐
 ├─ K2 FindStatus + FindCommand (MarkedCore) + tests                   │ parallel, disjoint files,
 ├─ K3 FindBar view, FindController, menu + Ctrl-F, ReaderView         │ one builder each, own worktree
 └─ K4 WebView find bridge (coordinator) + refresh after render        ┘
I3 integrate + live check (sequential)
```

Critical path: W3 → join(K1–K4) → I3. Expected longest: K1 (DOM text index and range mapping).

## Own decisions

- Highlighting uses the **CSS Custom Highlight API** (`CSS.highlights`, `Highlight`, `Range`), not `<mark>`/`<span>` wrapping. It never changes the DOM, so it cannot break text nodes, collide with S8's `<mark>`, disturb mermaid, or need cleanup before a render; ranges may cross element boundaries natively. Styles live in `base.css`: `::highlight(find-hit)`, `::highlight(find-current)`. W3.3 spikes it in the app's `.defaultClient` world; if the spike fails, K1 falls back to per-text-node `<span class="find-hit">` wrapping (same JS API, more code) — record the result in this plan
- Matching: case-insensitive, Unicode-aware: escape the query, turn each run of whitespace into `\s+`, build `new RegExp(…, "giu")`; match offsets index the original text (no lower-casing, so no length drift). Non-overlapping, left to right. Empty query → no matches
- Text index: walk text nodes under `#content` in document order, skipping nodes inside `div.mermaid`, `svg`, `script`, `style`, and the `.render-error` box. Join them into one string; where the nearest block ancestor changes, insert `\u0000` so a match never spans two blocks ("Para 1" + "Para 2" ≠ "1Para"). Frontmatter text is searchable
- State lives in JS (`query`, `index`) so the `decorate` hook can re-apply after every render without a Swift round trip; Swift mirrors `{count, index}` for the bar label. After a render, the coordinator asks JS for the state (only while the bar is open)
- Re-apply after render keeps the current index when it still exists, else clamps to the last match; it does not scroll (S1's scroll-to-change wins on a reload)
- Navigation wraps; the current match scrolls into view (`range.getBoundingClientRect()` → smooth `scrollBy` to center)
- Keys: Cmd-F (menu item) and Ctrl-F (local `NSEvent` key-down monitor; SwiftUI menus cannot show two shortcuts for one item) open the bar and focus the field; Enter / Shift-Enter in the field; Cmd-G / Shift-Cmd-G menu items; Esc closes. Commands reach the key window's `FindController` through `@FocusedValue`
- No case-sensitivity, regex, or whole-word options (Q6 asked for none)

## Frozen contracts (W3)

```js
// Resources/js/find.js — window.Marked.find (app world)
//   set(query)  -> {count, index}   // index -1 when count 0; scrolls to match 0
//   step(dir)   -> {count, index}   // dir +1 / -1, wraps; scrolls to the new current
//   clear()     -> {count: 0, index: -1}
//   state()     -> {count, index}
// Pure, exported for node: matchOffsets(text, query) -> [[start, end], ...]
```

```swift
// MarkedCore/Find.swift
public struct FindStatus: Equatable, Sendable {
    public let count: Int
    public let index: Int            // -1 when no current match
    public init(count: Int, index: Int)
    public static let empty: FindStatus   // (0, -1)
    public func label(query: String) -> String   // "" | "No results" | "3 of 12"
}
public enum FindCommand: Equatable, Sendable { case set(String), next, previous, clear }

// Marked/FindController.swift (app)
@MainActor final class FindController: ObservableObject {
    @Published var isVisible: Bool
    @Published var query: String
    @Published private(set) var status: FindStatus
    var perform: (FindCommand) async -> FindStatus   // set by the coordinator
    func show(); func hide(); func next(); func previous(); func update(_ query: String)
}
```

## File ownership

| File | Owner |
|---|---|
| Stubs: `Find.swift`, `FindController.swift`, `js/find.js` (contract, returns empty state); `base.css` highlight rules; `userScripts` line for `find.js` | W3 (frozen after) |
| `Resources/js/find.js` (bodies), `Tests/js/find.test.mjs` | K1 |
| `Sources/MarkedCore/Find.swift` (bodies), `Tests/MarkedCoreTests/FindTests.swift` | K2 |
| `Sources/Marked/{FindBar,FindController,MarkedApp,ReaderView}.swift` | K3 |
| `Sources/Marked/WebView.swift` | K4 |

## Tasks

### W3 — stubs, CSS, spike (sequential, main loop)

- [ ] W3.1 Branch `s3-find` from `s2-styles`
- [ ] W3.2 Stubs per "Frozen contracts" (Swift compiles, JS returns `{count: 0, index: -1}`); append `resource("find", "js", subdirectory: "js")` to `userScripts`; `FindController.perform` default returns `.empty`
- [ ] W3.3 Spike (temporary harness, not committed): in the running app, from `.defaultClient`, `CSS.highlights.set("find-hit", new Highlight(r))` on a range over a word, then check `CSS.highlights.has("find-hit")` is true and `#content.innerHTML` is unchanged. Record pass/fail here; fail → K1 uses span wrapping
- [ ] W3.4 `base.css`: `::highlight(find-hit) { background: #ffe58a }`, `::highlight(find-current) { background: #ff9632 }`
- [ ] W3.5 `make test` + `make app` green → commit → fork worktrees

### K1 — find.js (builder)

- [ ] K1.1 Node tests first (`Tests/js/find.test.mjs`) for `matchOffsets`: case-insensitive; Unicode (`É` vs `é`); regex metacharacters in the query are literal (`a.b`, `(x)`, `\`); whitespace runs in the query match any whitespace run; non-overlapping (`aa` in `aaaa` → 2); `\u0000` block boundary blocks a match; empty query → `[]`; offsets point into the original text
- [ ] K1.2 Pure helper `step(index, count, dir)` with wrap; tests: forward wrap, back wrap, count 0 → -1
- [ ] K1.3 DOM layer: text index (skip rules and `\u0000` boundaries from "Own decisions"), map match offsets to `Range`s across text nodes, register `find-hit` (all) and `find-current` (one), scroll current into view; `set`, `step`, `clear`, `state` per contract
- [ ] K1.4 `decorate` hook: if a query is active, rebuild ranges after each render (no scroll); keep index or clamp
- [ ] K1.5 Export `matchOffsets` and `step` for node behind the `typeof module` guard (as `scroll.js`); browser path must not throw without `module`

### K2 — FindStatus (builder)

- [ ] K2.1 Tests first (no `import Foundation`): `label` → `""` for an empty query; `"No results"` for count 0; `"1 of 3"` for index 0; `.empty` == (0, -1)
- [ ] K2.2 Implement

### K3 — UI (builder)

- [ ] K3.1 `FindController` bodies: `update(query)` → `status = await perform(.set(query))`; `next`/`previous` → `.next`/`.previous`; `hide()` → `perform(.clear)`, `isVisible = false`; `show()` → `isVisible = true` (focus handled by the view)
- [ ] K3.2 `FindBar` view: `TextField` (focused on show via `@FocusState`), status label, previous/next buttons, close button; `.onSubmit` → next; Shift-Enter → previous (`onKeyPress` with `.shift`); Esc (`.onExitCommand` / `onKeyPress(.escape)`) → hide. Debounce typing lightly (~150 ms) before `update`
- [ ] K3.3 `ReaderView`: own a `@StateObject FindController`; show `FindBar` in the top `safeAreaInset` above the existing banner; `.focusedSceneValue(\.findController, controller)`; pass the controller into `WebView`
- [ ] K3.4 `MarkedApp`: `CommandGroup(after: .textEditing)` with "Find…" (Cmd-F), "Find Next" (Cmd-G), "Find Previous" (Shift-Cmd-G), acting on `@FocusedValue(\.findController)`; disabled when nil. Ctrl-F: a local `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed once that maps Control-F (no other modifiers) to the focused controller's `show()` and swallows the event
- [ ] K3.5 `make app` builds with no warnings in owned files

### K4 — WebView bridge (builder)

- [ ] K4.1 `WebView` takes the `FindController`; the coordinator sets `controller.perform` to call `Marked.find.set/step/clear` via `callAsyncJavaScript(…, in: nil, contentWorld: .defaultClient)` and decode `{count, index}` into `FindStatus` (decode miss → `.empty`, logged)
- [ ] K4.2 After each successful render (inside the existing send closure, after the result decodes), if `controller.isVisible`, fetch `Marked.find.state()` and publish it
- [ ] K4.3 `make app` builds; `make test` green

### I3 — integrate + live check (sequential, main loop)

- [ ] I3.1 Merge K1–K4 (copy files); `make test` (Swift + JS); `make install`
- [ ] I3.2 Fixture with: a word in plain text, in `**bold**`, split across `**bo**ld`, inside a link, in frontmatter, across a soft line break ("should\nrender"), and in a code block; a sentence ending a paragraph followed by one starting the next. Temporary env-guarded harness (not committed) drives `FindController` directly:
  - counts match the fixture for each query; the cross-paragraph query finds nothing
  - `next` × (count + 1) wraps to index 0; `previous` from 0 wraps to the last
  - `#content.innerHTML` unchanged after find (no DOM mutation)
  - append to the file → highlights survive the render, count updates
  - `clear` → `CSS.highlights` empty
  - pause ≥ 2 s between app launches (Launch Services `-600` race seen in S2)
- [ ] I3.3 Manual (needs a person at the keyboard): Cmd-F and Ctrl-F open the bar with focus in the field; Enter / Shift-Enter / Cmd-G / Shift-Cmd-G move; Esc closes and clears; the label reads "n of m"
- [ ] I3.4 code-reviewer loop until clean (max 5); commit on `s3-find`; tick S3 in `design.md`

## Merge conflicts

- S2 is already merged, so C1 (`MarkedApp.commands`), C3 (`WebView`), and C4 (`ReaderView`) are plain sequential edits on this branch, not conflicts
- C2 `userScripts`: one line in W3

## Resolved questions (user, 2026-10-09)

1. Case-insensitive only, no options: yes
2. Frontmatter text searchable: yes
3. Find bar above the error banner when both show: yes

No open questions.
