# S2 implementation plan — styles (parallel)

Source: `design.md` (S2 row, Styles bullet, Render lifecycle "send style then render"), `grill.md` Q5. Size: 1 pt (`estimates.md`). Builds on `s4-frontmatter` @ `fdc66b9`.

Done = Cmd-1 / Cmd-2 / Cmd-3 switch every open window between monospace, serif, and sans-serif with no page reload and no scroll jump to the top; the View menu shows a check next to the current style; the choice survives a relaunch; first launch uses sans; frontmatter and code blocks stay monospace in every style; `make test` green; live check passes.

## Shape

```
W2 frozen stubs + placeholder CSS (sequential, small)
 ├─ Y1 Style enum + tests (MarkedCore)                  ┐
 ├─ Y2 styles/*.css + node test                         │ parallel, disjoint files,
 ├─ Y3 RenderQueue style seam + tests (MarkedCore)      │ one builder each, own worktree
 └─ Y4 app wiring: @AppStorage, View menu, WebView      ┘
I2 integrate + live check (sequential)
```

Critical path: W2 → join(Y1–Y4) → I2.

## Own decisions

- One source of truth: `@AppStorage("style")` (UserDefaults). Every `ReaderView` and the menu read it, so a switch reaches all windows and persists. Unknown stored value → sans
- Style values only set `:root` variables (design): `--font`, `--measure`, `--leading`. `base.css` already consumes them; `pre`, `code`, and `pre.frontmatter` set their own monospace font, so code and frontmatter never change
  - mono: `ui-monospace, Menlo, monospace`; `--measure: 80ch`; `--leading: 1.5`
  - serif: `"New York", ui-serif, Georgia, serif`; `--measure: 38em`; `--leading: 1.65`
  - sans: `-apple-system, system-ui, sans-serif`; `--measure: 46em`; `--leading: 1.6` (today's `base.css` defaults)
- Swap = `Marked.setStyle(cssText)` (S0 bridge, already in `marked.js`); no reload, so scroll position and find state survive
- The design's "send style then render" lives in `RenderQueue`, so the ready gate and generation rules stay in one tested place. Style sends and renders share the queue's **single in-flight slot**; `pump()` always dispatches a pending style before a pending render. So: a submit that arrives while the initial style is in flight waits for it; a style change waits for a render in flight (and vice versa); every completion, style or render, carries the shell generation and is discarded entirely when stale (S0 rule), so an old style send cannot pump the new shell or report a stale failure
- Menu: `CommandGroup(after: .toolbar)` in the View menu: three `Toggle`s bound to the stored style, so the menu shows a check; `.keyboardShortcut("1")`, `"2"`, `"3"` (Cmd is the default modifier). Order follows the request: 1 mono, 2 serif, 3 sans
- Scroll on a style switch: the browser keeps `scrollY`, so the reader may land a little off after the reflow. Accepted (user, 2026-10-09)

## Frozen contracts (W2)

```swift
// MarkedCore/Style.swift
public enum Style: String, CaseIterable, Sendable {
    case mono, serif, sans
    public static let `default`: Style       // .sans
    public init(stored: String?)             // unknown or nil → .sans
    public var title: String                 // "Monospace", "Serif", "Sans-serif"
    public var shortcut: Character           // "1", "2", "3"
    public var resource: String              // "mono", "serif", "sans" (file in Resources/styles/)
}

// MarkedCore/RenderQueue.swift (additions; existing API unchanged)
public var sendStyle: (String) async throws -> Void      // default: no-op
public var onStyleApplied: () -> Void                    // default: no-op; a style send succeeded
public var onStyleFailure: (Error) -> Void               // default: no-op; separate from onFailure (render)
public func setStyle(_ css: String)
```

## File ownership

| File | Owner |
|---|---|
| Stubs: `Style.swift`, `RenderQueue` additions; placeholder `Resources/styles/{mono,serif,sans}.css` (`:root {}`) | W2 (frozen after) |
| `Sources/MarkedCore/Style.swift` (bodies), `Tests/MarkedCoreTests/StyleTests.swift` | Y1 |
| `Resources/styles/{mono,serif,sans}.css` (content), `Tests/js/styles.test.mjs` | Y2 |
| `Sources/MarkedCore/RenderQueue.swift` (style seam bodies), `Tests/MarkedCoreTests/RenderQueueTests.swift` (add tests) | Y3 |
| `Sources/Marked/{MarkedApp,ReaderView,WebView}.swift` | Y4 |

## Tasks

### W2 — stubs (sequential, main loop)

- [ ] W2.1 Branch `s2-styles` from `s4-frontmatter`
- [ ] W2.2 `Style.swift`: cases real; `default` = `.sans`; `init(stored:)` → `.sans`; `title`/`shortcut`/`resource` placeholders that compile (e.g. `rawValue`, `"0"`)
- [ ] W2.3 `RenderQueue`: every frozen addition, so Y4 builds without Y3: `public var sendStyle: (String) async throws -> Void = { _ in }`, `public var onStyleApplied: () -> Void = {}`, `public var onStyleFailure: (Error) -> Void = { _ in }`, `public func setStyle(_ css: String) {}`
- [ ] W2.4 `Resources/styles/{mono,serif,sans}.css` each `:root {}`
- [ ] W2.5 `make test` + `make app` green → commit → fork worktrees

### Y1 — Style enum (builder)

- [ ] Y1.1 Tests first (no `import Foundation`): `allCases == [.mono, .serif, .sans]`; shortcuts `"1"`, `"2"`, `"3"` in that order and unique; titles; resources match raw values; `default == .sans`; `init(stored: "serif") == .serif`; `init(stored: nil)` and `init(stored: "bogus")` → `.sans`
- [ ] Y1.2 Implement

### Y2 — CSS files (builder)

- [ ] Y2.1 Node test first (`Tests/js/styles.test.mjs`, `node:fs` + `node:assert`): for each of `mono`, `serif`, `sans`: the file is exactly one `:root { … }` rule (no other selectors); it defines `--font`, `--measure`, `--leading` and nothing else; `mono`'s `--font` starts with `ui-monospace`; `serif`'s contains `serif`; `sans`' values equal the `:root` defaults in `base.css` (so first paint and the sans file never disagree)
- [ ] Y2.2 Write the three files with the values in "Own decisions"

### Y3 — RenderQueue style seam (builder)

- [ ] Y3.1 Tests first (extend `RenderQueueTests`, reuse its suspendable fakes; add a fake `sendStyle` that records and suspends):
  - `setStyle` before ready → no `sendStyle`; `markReady` with pending style + pending render → style sent, render **not** sent until the style send completes; then render sent (record order)
  - submit while the initial style send is suspended → still no render; resume style → exactly one render with the latest source
  - `setStyle` twice before ready → only the latest sent
  - `setStyle` while a render is in flight → style waits; sent after the render completes
  - reload while the style send is suspended: `shellWillReload` + `markReady` → the current style is sent again (new generation) before the re-sent render; then resume the **old** style send with success, and (second test) with a throw → no extra send, no `onStyleApplied`, no `onStyleFailure`, the new shell's in-flight op unaffected
  - style failure: `sendStyle` throws → `onStyleFailure` called once, `onFailure` not called, `onStyleApplied` not called; the pending render is still sent; a later render success does not call `onStyleApplied`
  - no automatic retry after a style failure; the next `setStyle` or a reload + `markReady` sends it again
  - newer request survives a failed send: send A (suspended), `setStyle(B)`, fail A → `onStyleFailure` once, then B is sent; B succeeds → `onStyleApplied`
  - newer request survives a successful send: send A (suspended), `setStyle(B)`, A succeeds → B is sent next
  - success → `onStyleApplied` called once
  - no style ever set → `markReady` sends no style; existing render tests stay green
- [ ] Y3.2 Implement in `RenderQueue`: `currentStyle: String?` (latest requested) and `pendingStyle: String?` (not yet applied in this generation). `setStyle(css)`: set both, `pump()`. `pump()`: guard `ready`, nothing in flight; if `pendingStyle` → dispatch it (on completion, success **or failure**, clear `pendingStyle` only if it still equals the CSS that was sent, so a newer request made during the send is kept and dispatched next; on failure also call `onStyleFailure` — no retry of the failed CSS itself); else dispatch the pending render as today. Both kinds capture `generation`; stale completions return before touching any state or calling any callback. `shellWillReload` also sets `pendingStyle = currentStyle`

### Y4 — app wiring (builder)

- [ ] Y4.1 `MarkedApp`: `@AppStorage("style") private var stored = Style.default.rawValue`; `.commands { CommandGroup(after: .toolbar) { ForEach(Style.allCases, id: \.self) { s in Toggle(s.title, isOn: Binding(get: { Style(stored: stored) == s }, set: { if $0 { stored = s.rawValue } })).keyboardShortcut(KeyEquivalent(s.shortcut)) } } }`
- [ ] Y4.2 `ReaderView`: `@AppStorage("style")`; pass `Style(stored:)` into `WebView`. Add `@State styleFailure: String?` beside the existing `failure`; subtitle shows "Render failed: …" and/or "Style failed: …" (both when both are set)
- [ ] Y4.3 `WebView`: `let style: Style`; coordinator sets `queue.sendStyle` = `callAsyncJavaScript("Marked.setStyle(css)", arguments: ["css": …], in: nil, contentWorld: .defaultClient)`; in `makeNSView` and `updateNSView`, call `coordinator.apply(style)` → when the style differs from the last applied one, read `Resources/styles/<resource>.css` (`resource(_:_:subdirectory: "styles")`) and `queue.setStyle(css)`. The coordinator caches the last **requested** style only to skip re-reading the same file; retry after a failure is the queue's job (next `setStyle` or reload). Wire `queue.onStyleFailure` → log + `setStyleFailure("\(err)")`, `queue.onStyleApplied` → `setStyleFailure(nil)`. The existing render-success `setFailure(nil)` stays, and clears only the render failure
- [ ] Y4.4 `make app` builds with no warnings in owned files; `make test` stays green

### I2 — integrate + live check (sequential, main loop)

- [ ] I2.1 Merge Y1–Y4 (copy files); `make test` (Swift + JS); `make install`
- [ ] I2.2 Temporary env-guarded harness (not committed), fixture with frontmatter, a code block, and 40 paragraphs:
  - launch with `-style serif` (UserDefaults argument domain) → body `font-family` starts with `"New York"`; `pre.frontmatter` and `pre` stay `ui-monospace`
  - launch with no stored value (`defaults delete com.example.Marked style`) → sans
  - with two windows open, the harness sets `UserDefaults.standard.set("mono", forKey: "style")` → both windows switch to `ui-monospace` within 1s; `Marked.token` unchanged (no reload); `scrollY` > 0 kept after scrolling down first
  - relaunch → mono restored
  - style failure path (harness forces `sendStyle` to throw once): subtitle shows "Style failed", stays after the next successful render, clears after the next successful style send
- [ ] I2.3 Manual (needs a person at the keyboard; cannot be scripted without Accessibility permission): Cmd-1/2/3 switch styles; the View menu shows the check on the current style
- [ ] I2.4 code-reviewer loop until clean (max 5); commit on `s2-styles`; tick S2 in `design.md`

## Merge conflicts

- C1 `MarkedApp.commands`: S2 adds the View-menu group; S3 adds Find items later
- C3 `WebView` coordinator: S2 adds `sendStyle` and `apply(style)`; S3 and S6 edit other parts
- `RenderQueue`: additive seam only; existing API and tests unchanged

## Resolved questions (user, 2026-10-09)

1. Style values as listed in "Own decisions": accepted
2. Small scroll jump from reflow on a style switch: accepted (no anchor step)

No open questions.
