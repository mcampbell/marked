# S3 implementation plan — find (parallel)

Source: `design.md` (S3 row, "Find skips mermaid", "Find must match across inline element boundaries", soft breaks), `grill.md` Q6, D30. Size: 2 pts (`estimates.md`). Builds on `s2-styles` @ `960d000`.

Done = Cmd-F or Ctrl-F opens a find bar in the current window; typing highlights every match and shows "n of m"; Enter / Cmd-G go to the next match, Shift-Enter / Shift-Cmd-G to the previous, wrapping at the ends, with the current match scrolled into view; Esc closes the bar and clears the highlights; a live reload keeps the highlights and updates the count; a shell reload (web process crash) restores the search; matches work across bold/italic/link boundaries and across wrapped lines; a find failure shows "Find failed", never a false "No results"; `make test` green; live check passes.

## Shape

```
W3 frozen stubs + CSS + spike (sequential)
 ├─ K1 js/find.js: pure matcher + highlight backend + hook + node tests   ┐
 ├─ K2 FindSession + FindStatus (MarkedCore) + tests                       │ parallel, disjoint files,
 ├─ K3 FindBar view, FindController, menu + Ctrl-F, ReaderView             │ one builder each, own worktree
 └─ K4 WebView bridge: send, ready, reload, render-complete hooks          ┘
I3 integrate + live check (sequential)
```

Critical path: W3 → join(K1–K4) → I3. Expected longest: K1 or K2.

## Own decisions

- **One state machine, in MarkedCore.** `FindSession` (like `RenderQueue`: `@MainActor`, injected async `send`, fully unit-tested) owns visibility, the desired query, readiness, request ordering, restore after a shell reload, and errors. The app's `FindController` is a thin `ObservableObject` that forwards UI intents to the session and republishes `session.onChange` for SwiftUI. The bridge (K4) only wires `send` and calls `markReady` / `shellWillReload` / `renderDidComplete`; it never sets status itself (review item 1)
- **Ordering (latest wins).** Every request to JS carries a session `revision` (incremented on each new request). A result is applied only if its revision is still the latest; older results are dropped. `close()` bumps the revision, so a late `.set` result cannot repaint a closed bar's label. The view's debounce `Task` is cancelled in `hide()`, and `FindSession.type(_:)` is ignored while not visible, so a debounced query cannot reach JS after Esc (review item 2). Requests are not queued: JS calls are cheap and the revision rule makes order irrelevant for the label; JS itself applies `set`/`step`/`clear` in call order
- **Readiness and shell reload.** Before `markReady`, the session sends nothing; it keeps the desired query. On `markReady` (shell `didFinish`), if the bar is visible with a non-empty query, it sends `.restore(query, index)` — re-highlight without scrolling, so S1's scroll-to-change is not overridden. `shellWillReload()` sets `ready = false` and bumps the revision (the old page's results are void); the next `markReady` restores. A plain content render keeps JS state; `renderDidComplete()` asks for `.state` to refresh the label (review item 3)
- **Errors.** `send` throws on a bridge failure or a decode miss. On a throw: keep the last good `status`, set `error` (label "Find failed"), log; never report it as zero matches. Errors clear on the next successful result. `renderDidComplete()` is fire-and-forget and non-throwing, called **after** the render result is decoded and returned to the queue — a failed state refresh can never turn a displayed render into a render failure (review item 4)
- **Highlight backend.** Preferred: the **CSS Custom Highlight API** (`CSS.highlights`, `Highlight`, `Range`): no DOM change, no cleanup, ranges cross element boundaries natively. Fallback (only if the W3 spike fails): wrap each match segment in `<span class="find-hit">` (current: `find-hit find-current`), unwrap and `normalize()` before every re-apply and on `clear`. Both backends sit behind the same `Marked.find` API; W3 records which one K1 builds, and the I3 checks for that backend apply (review item 5)
- **Matching.** Case-insensitive, Unicode-aware: escape the query, turn each whitespace run into `\s+`, `new RegExp(…, "giu")`; offsets index the original text. Non-overlapping, left to right. Empty query → no matches
- **Text index.** Text nodes under `#content` in document order, skipping `div.mermaid`, `svg`, `script`, `style`, `.render-error`, and (fallback backend) existing `.find-hit` wrappers are unwrapped first. Joined into one string; where the nearest block ancestor changes, insert `\u0000` so a match never spans two blocks. Frontmatter is searchable (D30)
- **JS state.** `query` and `index` live in JS so the `decorate` hook re-applies after every render (no scroll; keep the index or clamp to the last match)
- **Navigation** wraps; the current match scrolls into view (`range.getBoundingClientRect()` → smooth `scrollBy` to center). `restore` and the render hook never scroll
- **Keys.** Cmd-F (menu item) and Ctrl-F (local `NSEvent` key-down monitor; a SwiftUI menu item has one shortcut) open the bar and focus the field; Enter / Shift-Enter in the field; Cmd-G / Shift-Cmd-G menu items; Esc closes. Commands reach the key window's `FindController` through `@FocusedValue`
- Case-insensitive only, no options; bar above the error banner (D30)

## Frozen contracts (W3)

```js
// Resources/js/find.js — window.Marked.find (app world). All return {count, index}; index -1 when count 0.
//   set(query)            // highlight, current = 0, scroll to it
//   step(dir)             // dir +1 / -1, wraps, scroll to it
//   restore(query, index) // highlight, current = clamp(index), NO scroll
//   clear()               // remove all highlights, forget the query
//   state()               // current {count, index}, no side effects
// Pure, exported for node: matchOffsets(text, query) -> [[start, end], ...]; step(index, count, dir) -> index
```

```swift
// MarkedCore/Find.swift
public struct FindStatus: Equatable, Sendable {
    public let count: Int
    public let index: Int                      // -1 when no current match
    public init(count: Int, index: Int)
    public static let empty: FindStatus        // (0, -1)
}
public enum FindCommand: Equatable, Sendable {
    case set(String), step(Int), restore(String, Int), clear, state
}
public struct FindView: Equatable, Sendable {  // what the bar shows
    public let isVisible: Bool
    public let label: String                   // "" | "No results" | "3 of 12" | "Find failed"
}
@MainActor public final class FindSession {
    public init(send: @escaping (FindCommand) async throws -> FindStatus)
    public var onChange: (FindView) -> Void    // default: no-op
    public private(set) var query: String
    public func open()
    public func close()
    public func type(_ query: String)          // ignored while closed
    public func next()
    public func previous()
    public func markReady()
    public func shellWillReload()
    public func renderDidComplete()            // non-throwing, fire-and-forget
}

// Marked/FindController.swift (app): thin ObservableObject over FindSession
@MainActor final class FindController: ObservableObject {
    @Published private(set) var view: FindView
    @Published var text: String                // bound to the field; debounced into session.type
    let session: FindSession
    init(session: FindSession)
    func show(); func hide(); func next(); func previous()
}
```

## File ownership

| File | Owner |
|---|---|
| Stubs for every contract above; `base.css` highlight rules (both backends); `userScripts` line for `find.js` | W3 (frozen after) |
| `Resources/js/find.js` (bodies), `Tests/js/find.test.mjs` | K1 |
| `Sources/MarkedCore/Find.swift` (bodies), `Tests/MarkedCoreTests/FindTests.swift` | K2 |
| `Sources/Marked/{FindBar,FindController,MarkedApp,ReaderView}.swift` | K3 |
| `Sources/Marked/WebView.swift` | K4 |

## Tasks

### W3 — stubs, CSS, spike (sequential, main loop)

- [ ] W3.1 Branch `s3-find` from `s2-styles`
- [ ] W3.2 Stubs per "Frozen contracts": Swift compiles (`FindSession` methods no-ops, `onChange` default no-op); JS returns `{count: 0, index: -1}` from every method; append `resource("find", "js", subdirectory: "js")` to `userScripts`
- [ ] W3.3 Spike in the running app (temporary harness, not committed), from the `.defaultClient` world: register `find-hit` on a `Range` over a known word; then (a) `CSS.highlights.has("find-hit")`, (b) `#content.innerHTML` unchanged, and (c) **visible paint**: `WKWebView.takeSnapshot` and sample the pixel at the centre of the range's rect — it must be the `find-hit` colour (within a small tolerance), and plain text elsewhere must not be. All three pass → Highlight API; any fails → span fallback. Record the result and the backend here
- [ ] W3.4 `base.css`: `::highlight(find-hit) { background: #ffe58a } ::highlight(find-current) { background: #ff9632 }` and the fallback equivalents `.find-hit { background: #ffe58a } .find-current { background: #ff9632 }` (keep both; the unused pair costs nothing)
- [ ] W3.5 `make test` + `make app` green → commit → fork worktrees

### K1 — find.js (builder)

- [ ] K1.1 Node tests first (`Tests/js/find.test.mjs`) for `matchOffsets`: case-insensitive; Unicode (`É`/`é`); regex metacharacters literal (`a.b`, `(x)`, `\`); whitespace runs match any whitespace run; non-overlapping (`aa` in `aaaa` → 2); `\u0000` blocks a match; empty query → `[]`; offsets point into the original text
- [ ] K1.2 `step(index, count, dir)`: forward wrap, back wrap, count 0 → -1; tests
- [ ] K1.3 DOM layer on the backend W3 chose: text index, offsets → ranges, highlight all + current, scroll current; `set`, `step`, `restore` (no scroll), `clear`, `state` per contract
- [ ] K1.4 `decorate` hook: with an active query, re-apply after each render (no scroll; keep index or clamp)
- [ ] K1.5 Export the pure helpers behind the `typeof module` guard (as `scroll.js`)

### K2 — FindSession + FindStatus (builder)

- [ ] K2.1 Tests first (no `import Foundation`; a fake `send` that records commands and suspends on a continuation, like the `RenderQueue` tests):
  - closed → `type` sends nothing; `open` + `type("a")` → `.set("a")`, then the label "1 of 3" from the result
  - label rules: open with empty query → `""`; count 0 → "No results"; failure → "Find failed" and the previous label's status kept
  - latest wins: `type("a")` (suspended), `type("ab")` → resume "ab" first then "a" → label from "ab" only
  - type then close before the result: `type("a")` (suspended), `close()` → `.clear` sent; resume "a" → label stays `""`, `isVisible` false
  - `next`/`previous` → `.step(+1)` / `.step(-1)`; ignored when closed or query empty
  - not ready: `open` + `type("a")` before `markReady` → nothing sent; `markReady` → `.restore("a", 0)`
  - shell reload: with results showing (index 2), `shellWillReload()` → a suspended old result arriving later is dropped; `markReady` → `.restore("a", 2)`
  - `renderDidComplete()` while open → `.state`; while closed → nothing; a throwing `.state` → "Find failed", no throw escapes
  - error then success → error cleared
- [ ] K2.2 Implement per "Own decisions" (revision counter, ready flag, desired query and index, last good status, error)

### K3 — UI (builder)

- [ ] K3.1 `FindController`: forwards to the session; republishes `session.onChange` into `view`; debounces `text` changes (~150 ms) into `session.type`; `hide()` cancels the pending debounce `Task`, then `session.close()`
- [ ] K3.2 `FindBar` view: `TextField` bound to `text` (focused on show via `@FocusState`), label, previous/next buttons, close button; `.onSubmit` → next; Shift-Enter → previous (`onKeyPress` with `.shift`); Esc → hide
- [ ] K3.3 `ReaderView`: own the `FindController` (`@StateObject`, built with a `FindSession` whose `send` the coordinator sets); bar in the top `safeAreaInset` above the existing banner, shown when `view.isVisible`; `.focusedSceneValue(\.findController, controller)`; pass the session into `WebView`
- [ ] K3.4 `MarkedApp`: `CommandGroup(after: .textEditing)` with "Find…" (Cmd-F), "Find Next" (Cmd-G), "Find Previous" (Shift-Cmd-G) on `@FocusedValue(\.findController)`, disabled when nil. Ctrl-F: one local `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` mapping Control-F (no other modifiers) to the focused controller's `show()`, swallowing the event
- [ ] K3.5 `make app` builds with no warnings in owned files

### K4 — WebView bridge (builder)

- [ ] K4.1 `WebView` takes the `FindSession`; the coordinator sets `session.send` to call the matching `Marked.find.*` via `callAsyncJavaScript(…, in: nil, contentWorld: .defaultClient)` and decode `{count, index}`; a decode miss **throws** (the session turns it into "Find failed")
- [ ] K4.2 `didFinish` → after `queue.markReady()`, `session.markReady()`; `webViewWebContentProcessDidTerminate` → `session.shellWillReload()` beside `queue.shellWillReload()`
- [ ] K4.3 After a render result decodes successfully in the send closure, call `session.renderDidComplete()` (non-throwing; it starts its own task) before returning the result — the render closure's outcome must not depend on it
- [ ] K4.4 `make app` builds; `make test` green

### I3 — integrate + live check (sequential, main loop)

- [ ] I3.1 Merge K1–K4 (copy files); `make test` (Swift + JS); `make install`
- [ ] I3.2 Fixture with: a word in plain text, in `**bold**`, split across `**bo**ld`, inside a link, in frontmatter, across a soft line break ("should\nrender"), and in a code block; a sentence ending one paragraph and another starting the next. Temporary env-guarded harness (not committed) drives the `FindController`:
  - counts match the fixture for each query; the cross-paragraph query finds nothing
  - from index 0, `next` × `count` returns to index 0; `previous` from 0 goes to `count - 1`
  - append to the file → highlights survive the render, the count updates, scroll follows S1 (not find)
  - backend checks — Highlight API: `#content.innerHTML` unchanged after find, `CSS.highlights` empty after `clear`; span fallback: `textContent` unchanged after find, no `.find-hit` left after `clear`
  - shell reload restore: harness calls `webViewWebContentProcessDidTerminate`'s path (shell reload) with the bar open → after `didFinish`, highlights and the label return, no scroll jump
  - forced bridge failure (harness makes `send` throw once) → label "Find failed", then a successful `next` clears it
  - pause ≥ 2 s between app launches (Launch Services `-600` race seen in S2)
- [ ] I3.3 Manual (needs a person at the keyboard): Cmd-F and Ctrl-F open the bar with focus in the field; Enter / Shift-Enter / Cmd-G / Shift-Cmd-G move; Esc closes and clears (also when pressed right after typing); the label reads "n of m"
- [ ] I3.4 code-reviewer loop until clean (max 5); commit on `s3-find`; tick S3 in `design.md`

## Merge conflicts

- S2 is already merged, so `MarkedApp.commands`, `WebView`, and `ReaderView` are plain sequential edits on this branch
- `userScripts`: one line in W3

## Resolved questions (user, 2026-10-09)

1. Case-insensitive only, no options: yes
2. Frontmatter text searchable: yes
3. Find bar above the error banner when both show: yes

No open questions.
