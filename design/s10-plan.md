# S10 implementation plan — TOC sidebar

Source: `design.md` (S10 row, "S10 TOC rules", C1–C4), `grill.md` D36, D37, D40, D41, D45. Size: 2 pts (`estimates.md`). Builds on `s10-s13-design` (= `main` + S10–S13 design).

Done = View > Show/Hide Sidebar (Ctrl-Cmd-S) toggles a leading sidebar in every window at once; hidden on first launch; the open state survives relaunch; the sidebar lists every `h1`–`h6` of `#content` in document order, indented by level; it refreshes after every render (live reload and shell reload included); a click on a row scrolls that heading to the top, instantly, no flash; a doc with no headings shows "No headings"; find (Cmd-F), banner, live scroll still work with the sidebar open; `make test` green; live check passes.

## Shape

```
W10 stubs + sidebar spike (sequential, main loop)
 ├─ K1 TOC.swift (MarkedCore) + Swift tests   ┐
 ├─ K2 js/toc.js + node tests                 │ parallel, disjoint files, one builder each, own worktree
 └─ K3 app: TOCSidebar + ReaderView + bridge  ┘
I10 integrate + live check (sequential, main loop)
```

Critical path: W10 (spike gates K3) → join(K1–K3) → I10. Expected longest: K3.

## Own decisions

- **Pure model in MarkedCore.** `TOC.parse(raw) -> [TOCEntry]` validates the bridge payload and computes `depth = level − smallest level in the doc` (gaps kept: `h1`, `h3` → depth 0, 2). Bad payload → throws `TOCError`; the coordinator logs it and shows an empty list (design). `TOCEntry.title` = text, or "—" when empty
- **JS is an API, not a hook** (design). Pure `tocHeadings(root)` and `tocGo(root, i)` take the root as a parameter so node tests run with fake objects (no DOM in node). `Marked.toc = { headings: () => tocHeadings(content), go: (i) => tocGo(content, i) }`. Query `h1, h2, h3, h4, h5, h6` on `#content` (one query, document order; raw-HTML headings included). `level = Number(tagName[1])`; `text = textContent.replace(/\s+/g, " ").trim()`. `tocGo` accepts only an integer in range, else `false`; scroll `scrollIntoView({block: "start"})` (instant)
- **Go-to by index, not id** (D45): no dependency on `anchors.js` ids or hook order
- **Refresh = `onRendered` only.** `RenderQueue` re-renders after `shellWillReload` and fires `onRendered` again, so the shell-reload case needs no extra call. Style switch does not refresh (same headings). Each refresh bumps a counter; a result whose counter is stale is dropped (two quick renders cannot leave the older list)
- **App state:** `TOCController` (`@MainActor ObservableObject`, like `FindController`): `@Published private(set) var entries`, `var go: (Int) -> Void` set by the coordinator. `ReaderView` owns it (`@StateObject`) and passes it to `WebView`; coordinator holds it `weak`. S13 adds `current` here later; S10 adds nothing for S13
- **Click rule:** one `Button` per row (`.buttonStyle(.plain)`), never `List(selection:)` (design: S13 marks rows without scrolling). `go(i)` returning `false` is ignored: the next render refreshes the list
- **Row look:** `Text(title).lineLimit(1)`, tail truncation, leading padding `12 pt × depth`. No per-level font. Sidebar width `.navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)`
- **Visibility:** `@AppStorage("tocVisible") = false`; `NavigationSplitView(columnVisibility:)` with `Binding(get: { tocVisible ? .all : .detailOnly }, set: { tocVisible = $0 != .detailOnly })`. Every window reads the same key → all windows show/hide together (D40). `SidebarCommands()` in `MarkedApp.commands` gives the menu item + Ctrl-Cmd-S (spike W10.3)
- **Detail column** = today's `WebView` with its `safeAreaInset` (find bar, banner) and `navigationSubtitle` unchanged. `WebView.findController(in:)` walks subviews recursively, so it still finds the web view inside the split view (I10 checks)
- **Toolbar toggle button:** `NavigationSplitView` adds a sidebar button to the title bar. Keep it (discoverable, free). See unresolved Q1
- **Global names** stay specific (`TOC_SELECTOR`, `tocHeadings`, `tocGo`): one shared script scope

## Frozen contracts (W10)

```swift
// MarkedCore/TOC.swift
public struct TOCEntry: Equatable, Sendable {
    public let level: Int      // 1…6
    public let text: String    // as sent by JS (collapsed, trimmed)
    public let depth: Int      // level − min level in the doc
    public var title: String   // text, or "—" when empty
}
public struct TOCError: Error, CustomStringConvertible { public let raw: String }
public enum TOC {
    public static func parse(_ raw: Any?) throws -> [TOCEntry]   // stub: []
}

// Marked/TOCSidebar.swift
@MainActor final class TOCController: ObservableObject {
    @Published private(set) var entries: [TOCEntry] = []
    var go: (Int) -> Void = { _ in }
    func update(_ entries: [TOCEntry])
}
struct TOCSidebar: View { @ObservedObject var toc: TOCController }   // stub: Text("No headings")
```

```js
// Resources/js/toc.js (app world). Sets Marked.toc = { headings(), go(i) }. No hook.
// Pure, exported for node behind the `typeof module` guard:
//   tocHeadings(root) -> Array<{level: 1..6, text: string}>   // root null → []
//   tocGo(root, i) -> boolean
```

## File ownership

| File | Owner |
|---|---|
| `TOC.swift` stub; `toc.js` stub; `userScripts` line; `TOCSidebar.swift` stub; `WebView(toc:)` parameter; `SidebarCommands()` line; spike result | W10 (frozen after) |
| `Sources/MarkedCore/TOC.swift` (body), `Tests/MarkedCoreTests/TOCTests.swift` | K1 |
| `Resources/js/toc.js` (body), `Tests/js/toc.test.mjs` | K2 |
| `Sources/Marked/TOCSidebar.swift` (body), `ReaderView.swift`, `WebView.swift` (bridge + refresh) | K3 |

## Tasks

### W10 — stubs + spike (sequential, main loop)

- [ ] W10.1 Branch `s10-toc` from `s10-s13-design`
- [ ] W10.2 Stubs per "Frozen contracts"; append `resource("toc", "js", subdirectory: "js")` to `userScripts`; `WebView` gains `let toc: TOCController` (unused); `ReaderView` passes a `@StateObject` one; `MarkedApp.commands` gains `SidebarCommands()`
- [ ] W10.3 Spike (temp, env-guarded harness, not committed): wrap `ReaderView` body in the `NavigationSplitView` + `tocVisible` binding from "Visibility", sidebar = stub. Launch with `-ApplePersistenceIgnoreState YES`, two windows. Check: (a) sidebar hidden at first launch; (b) View menu has the sidebar item with Ctrl-Cmd-S (walk `NSApp.mainMenu`); (c) posted Ctrl-Cmd-S (`NSApp.postEvent`) → `UserDefaults "tocVisible"` flips `true`, both windows' first split subview not collapsed; again → `false`, both collapsed; (d) relaunch with `true` stored → sidebar shown. Any of (b)–(c) fails → fallback: drop `SidebarCommands()`, add `CommandGroup(replacing: .sidebar) { Toggle("Show Sidebar", isOn: $tocVisible).keyboardShortcut("s", modifiers: [.control, .command]) }` on `MarkedApp`'s own `@AppStorage("tocVisible")`; re-run (c). Record result here
- [ ] W10.4 Keep the spike's `NavigationSplitView` wrapper in `ReaderView` (K3 fills the sidebar). `make test` + `make app` green; app still renders → commit → fork worktrees

### K1 — TOC model (builder)

- [ ] K1.1 Tests first (`Tests/MarkedCoreTests/TOCTests.swift`, no `import Foundation`; payload as `[[String: Any]]` literals):
  - `[]` → `[]`
  - levels 2, 3 → depth 0, 1; levels 1…6 → depth 0…5; levels 2, 4 → depth 0, 2 (gaps kept); levels 3, 1, 2 → depth 2, 0, 1
  - text kept verbatim (`"Café 日本"`, `"C++ & Go!"`); `""` → `title == "—"`, `text == ""`; non-empty → `title == text`
  - throws `TOCError`: `nil`; `"x"`; `[1]`; `[["text": "a"]]` (no level); level `0`; level `7`; level `"1"`; level `1.5`; `[["level": 1]]` (no text); text `5`
  - order kept (3 entries in, same 3 out)
- [ ] K1.2 Implement (`import Foundation` in `TOC.swift` so the app's `NSNumber` levels cast with `as? Int`)

### K2 — toc.js (builder)

- [ ] K2.1 Node tests first (`Tests/js/toc.test.mjs`, `createRequire` as `anchors.test.mjs`; fake root `{querySelectorAll(sel) { seen = sel; return items } }`, fake headings `{tagName, textContent, scrollIntoView(o) { calls.push(o) }}`):
  - selector passed is exactly `"h1, h2, h3, h4, h5, h6"`
  - `H1`…`H6` → levels 1…6; order kept
  - text `"  a\n\tb  "` → `"a b"`; `"a  b"` → `"a b"`; `""` → `""`
  - `tocHeadings(null)` → `[]`
  - `tocGo(root, 1)` with 3 headings → `true`, only heading 1 got `scrollIntoView({block: "start"})`
  - `tocGo` with `-1`, `3`, `1.5`, `"0"`, `NaN` → `false`, no call; `tocGo(null, 0)` → `false`
- [ ] K2.2 Implement; `Marked.toc` set behind `typeof Marked !== "undefined"`, reading `document.getElementById("content")` at call time
- [ ] K2.3 `node --test 'Tests/js/*.test.mjs'` green

### K3 — app (builder)

- [ ] K3.1 `TOCController.update` sets `entries`. `TOCSidebar`: empty → `Text("No headings").foregroundStyle(.secondary)`, centered; else `List { ForEach(Array(entries.enumerated()), id: \.offset) { i, e in Button { toc.go(i) } label: { … } } }` per "Click rule" + "Row look"; `.navigationSplitViewColumnWidth` per "Row look"
- [ ] K3.2 Coordinator: `weak var tocController`; in `start`, `toc.go = { [weak web] i in Task { _ = try? await web?.callAsyncJavaScript("return Marked.toc.go(i)", arguments: ["i": i], in: nil, contentWorld: .defaultClient) } }`; `refreshTOC()`: bump counter, `callAsyncJavaScript("return Marked.toc.headings()", …)`, drop if stale, `toc.update(try TOC.parse(raw))`; on error `NSLog("Marked toc failed: …")` + `update([])`. `queue.onRendered` calls both `find?.renderDidComplete()` and `self?.refreshTOC()`. No change to the ready gate, `decidePolicyFor`, or the terminate path
- [ ] K3.3 `ReaderView`: sidebar = `TOCSidebar(toc:)`; detail = today's `WebView` + `safeAreaInset` + `navigationSubtitle`, unchanged
- [ ] K3.4 `make app` builds, no warnings; `make test` green

### I10 — integrate + live check (sequential, main loop)

- [ ] I10.1 Merge K1–K3; `make test`; `make install`
- [ ] I10.2 Fixture `toc dir/a.md` (space in path): frontmatter; `# Title`; `## Intro`; `## Intro`; `### *Em* and \`code\``;`#### H4`;`##### H5`;`###### H6`; raw`<h2 id="custom">Raw</h2>`; raw`<h3></h3>`; a fenced block containing`# not a heading`; a Mermaid block; 60 filler paragraphs between headings. Temporary env-guarded harness (not committed), reads`TOCController.entries` and calls `go(i)` (the `Button` action path):
  - entries = `Title, Intro, Intro, Em and code, H4, H5, H6, Raw, —` with depths `0,1,1,2,3,4,5,1,2`; no entry for the fence or frontmatter
  - `go(3)` → that heading's `getBoundingClientRect().top` ≈ 0 (± 2 px) right after the call (instant); page `Marked.token` unchanged (no reload); `go(99)` → no scroll, no crash
  - live reload: append `## New` → last entry `New`; replace the file with headingless text → entries `[]`, sidebar shows "No headings"; restore → entries back
  - shell reload (terminate path) → entries repopulate
  - toggle: posted Ctrl-Cmd-S → both windows show the sidebar, `tocVisible == true`; again → both hide; relaunch keeps the stored state
  - with the sidebar open: `WebView.findController(in: keyWindow)` non-nil; find `Intro` → `1 of 2`; error banner (rename the file away) still shows above the web view
  - ≥ 2 s between launches; `--args -ApplePersistenceIgnoreState YES`; pick window by `webView.url?.path`
- [ ] I10.3 Manual (person at the keyboard): click rows with the mouse → scrolls; Ctrl-Cmd-S from the keyboard; drag the sidebar edge; title-bar sidebar button toggles all windows
- [ ] I10.4 code-reviewer loop until clean (max 5) → `design/s10-review.md`; tick S10 in `design.md`; commit on `s10-toc`

## Merge conflicts

- C1 `.commands`: `SidebarCommands()` (W10); C2 `userScripts`: one line (W10); C3 coordinator: bridge + refresh (K3); C4 `ReaderView`: split-view wrap (W10/K3). All counted in `estimates.md`

## Deferred

- Scroll-spy (S13)
- Per-level fonts, collapsible levels, heading search in the sidebar (not asked)

## Unresolved questions

None. Resolved 2026-10-09:
1. ~~Title-bar sidebar toggle button?~~ Keep it (user, D46)
2. ~~Shell-reload refresh via `onRendered` only?~~ Yes (author, verified: `shellWillReload` sets `pending = latest`; `markReady` → `pump` → render → `onRendered`)
