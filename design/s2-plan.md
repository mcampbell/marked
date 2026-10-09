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
- The design's "send style then render" lives in `RenderQueue` as a style seam, so the ready gate stays in one tested place: before ready, the latest style waits; on `markReady` the style goes first, then the pending render; after `shellWillReload` the current style is sent again on the next `markReady`. Style sends never wait for a render in flight (the JS call is synchronous and independent of content)
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
- [ ] W2.3 `RenderQueue`: `public var sendStyle: (String) async throws -> Void = { _ in }`, `public func setStyle(_ css: String) {}`
- [ ] W2.4 `Resources/styles/{mono,serif,sans}.css` each `:root {}`
- [ ] W2.5 `make test` + `make app` green → commit → fork worktrees

### Y1 — Style enum (builder)

- [ ] Y1.1 Tests first (no `import Foundation`): `allCases == [.mono, .serif, .sans]`; shortcuts `"1"`, `"2"`, `"3"` in that order and unique; titles; resources match raw values; `default == .sans`; `init(stored: "serif") == .serif`; `init(stored: nil)` and `init(stored: "bogus")` → `.sans`
- [ ] Y1.2 Implement

### Y2 — CSS files (builder)

- [ ] Y2.1 Node test first (`Tests/js/styles.test.mjs`, `node:fs` + `node:assert`): for each of `mono`, `serif`, `sans`: the file is exactly one `:root { … }` rule (no other selectors); it defines `--font`, `--measure`, `--leading` and nothing else; `mono`'s `--font` starts with `ui-monospace`; `serif`'s contains `serif`; `sans`' values equal the `:root` defaults in `base.css` (so first paint and the sans file never disagree)
- [ ] Y2.2 Write the three files with the values in "Own decisions"

### Y3 — RenderQueue style seam (builder)

- [ ] Y3.1 Tests first (extend `RenderQueueTests`, reuse its fakes): `setStyle` before ready → no `sendStyle`; `markReady` with a pending style and a pending render → style sent, then render (record order); `setStyle` twice before ready → only the latest sent; `setStyle` while ready → sent at once, even with a render in flight; `shellWillReload` then `markReady` → current style sent again before the re-sent render; no style ever set → `markReady` sends no style; a throwing `sendStyle` → `onFailure` called, render still sent
- [ ] Y3.2 Implement: keep `currentStyle: String?`; `setStyle` stores it and sends when ready; `markReady` sends `currentStyle` (if any) before `pump()`; `shellWillReload` keeps `currentStyle`. Style sends run in a `Task` like renders; failures go to `onFailure`

### Y4 — app wiring (builder)

- [ ] Y4.1 `MarkedApp`: `@AppStorage("style") private var stored = Style.default.rawValue`; `.commands { CommandGroup(after: .toolbar) { ForEach(Style.allCases, id: \.self) { s in Toggle(s.title, isOn: Binding(get: { Style(stored: stored) == s }, set: { if $0 { stored = s.rawValue } })).keyboardShortcut(KeyEquivalent(s.shortcut)) } } }`
- [ ] Y4.2 `ReaderView`: `@AppStorage("style")`; pass `Style(stored:)` into `WebView`
- [ ] Y4.3 `WebView`: `let style: Style`; coordinator sets `queue.sendStyle` = `callAsyncJavaScript("Marked.setStyle(css)", arguments: ["css": …], in: nil, contentWorld: .defaultClient)`; in `makeNSView` and `updateNSView`, call `coordinator.apply(style)` → when the style differs from the last applied one, read `Resources/styles/<resource>.css` (`resource(_:_:subdirectory: "styles")`) and `queue.setStyle(css)`
- [ ] Y4.4 `make app` builds with no warnings in owned files; `make test` stays green

### I2 — integrate + live check (sequential, main loop)

- [ ] I2.1 Merge Y1–Y4 (copy files); `make test` (Swift + JS); `make install`
- [ ] I2.2 Temporary env-guarded harness (not committed), fixture with frontmatter, a code block, and 40 paragraphs:
  - launch with `-style serif` (UserDefaults argument domain) → body `font-family` starts with `"New York"`; `pre.frontmatter` and `pre` stay `ui-monospace`
  - launch with no stored value (`defaults delete com.example.Marked style`) → sans
  - with two windows open, the harness sets `UserDefaults.standard.set("mono", forKey: "style")` → both windows switch to `ui-monospace` within 1s; `Marked.token` unchanged (no reload); `scrollY` > 0 kept after scrolling down first
  - relaunch → mono restored
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
