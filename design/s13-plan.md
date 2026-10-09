# S13 implementation plan — TOC scroll-spy

Source: `design.md` (S13 row, "S13 scroll-spy rules", C3), `grill.md` D41, D45, D46. Size: 2 pts (`estimates.md`). Builds on `s10-s13-design` @ `8e5b878` (S10 + S11 + S12 merged). Branch `s13-scrollspy`.

Done = while the page scrolls, the sidebar marks the heading being read (last heading whose top is ≤ 8 px from the viewport top; none → no mark; scrolled to the end of a scrollable page → last heading whose top is inside the viewport, D47); the mark follows live reload, style switch, and window resize without a scroll; the marked row stays visible in the sidebar; marking never scrolls the page; a row click still jumps and then marks that row; each window marks independently; closing a window frees its coordinator (no retain cycle); `make test` green; live check passes.

## Shape

```
W13 stubs + message-handler spike (sequential, main loop)
 ├─ K1 TOC.current (MarkedCore) + Swift tests   ┐
 ├─ K2 js/toc.js spy + node tests               │ disjoint files; builders or sequential
 └─ K3 app: handler, TOCController.mark, sidebar ┘
I13 integrate + live check (sequential, main loop)
```

Critical path: W13 (spike gates K3) → K1–K3 → I13.

## Own decisions

- **Pure current-index rule in JS.** `tocCurrent({tops, height, atEnd}, edge = 8)` → index of the last `top ≤ edge`, else `-1`. Bottom rule (D47): `atEnd` → index of the last `top < height` (inside the viewport) when that is larger. `atEnd` = page can scroll (`scrollHeight > innerHeight`) and `scrollY + innerHeight ≥ scrollHeight − 1`; a doc that fits on one screen never has `atEnd`, so its last heading is not marked at load. Tops are in document order, but the function does not rely on it (scan all, keep last match)
- **Change-only posting in a pure closure.** `tocSpy(read, post)` → `{update(), reset()}`. `update()` calls `read()` (`{tops, height, atEnd}`), computes `tocCurrent`, posts only when it differs from the last posted value. `reset()` forgets the last value, then `update()` (so it always posts). First `update()` always posts (no last value)
- **Triggers** (app world only, behind `typeof Marked`): `scroll` on `window` (passive) and a `ResizeObserver` on `#content`, both through one `requestAnimationFrame` gate (at most one update per frame). `ResizeObserver` covers style switch, window resize, mermaid/image reflow, which move headings without a scroll event. A `position`-phase hook `tocSpyReset` calls `reset()` after each render (design). `Marked.render` swaps `innerHTML` only; the `#content` element stays, so the observer survives renders
- **Post target:** `window.webkit.messageHandlers.toc.postMessage(i)`. Missing (spike failure, node) → no-op guard, never throw inside a hook
- **Swift validates shape only, not range.** `TOC.current(raw) throws -> Int?`: integer `≥ -1` → `-1` maps to `nil` (no mark), `i ≥ 0` → `i`; anything else throws `TOCError`. Range is checked at display (`i < entries.count`). Reason: the `position` hook posts during the render, before `onRendered` → `refreshTOC` replaces `entries`, so a count check at receipt would compare the new index with the old list and drop valid marks. Changes the design's `current(raw, count:)`; design.md S13 rule updated with this plan
- **Bool payload not rejected.** JS `true` arrives as `NSNumber` 1 and cannot be told apart from `1` after bridging. The JS only posts integers; page JS is off, so no hostile poster exists. Documented, not tested
- **Handler:** `final class TOCMessages: NSObject, WKScriptMessageHandler { weak var coordinator }` (design's `WeakHandler`, named for its one use). Registered in `makeNSView` on the config before the `WKWebView` is created: `cfg.userContentController.add(TOCMessages(c), contentWorld: .defaultClient, name: "toc")`. The controller holds the handler strongly; the handler holds the coordinator weakly → no cycle. No `removeScriptMessageHandler` needed
- **Coordinator:** `func tocMessage(_ body: Any)` → `do { tocController?.mark(try TOC.current(body)) } catch { NSLog("Marked toc spy: \(error)") }`
- **Controller:** `TOCController` gains `@Published private(set) var current: Int?` and `func mark(_ i: Int?)`. `update(entries)` leaves `current` alone (the last post was computed on the new DOM)
- **Row look:** current row (`i == current`, `i < entries.count`) → `.fontWeight(.semibold)` + `.foregroundStyle(.tint)`. Others unchanged. No background bar (keeps `.plain` button look)
- **Keep visible:** `ScrollViewReader` around the `List`; rows get `.id(i)`; `.onChange(of: toc.current) { _, c in if let c { proxy.scrollTo(c) } }`, no animation, `anchor: nil` (minimal scroll; I13 checks it does not recenter on every change)
- **No loop:** a row click → `go(i)` → page scroll → spy posts `i` → `mark(i)` → sidebar `scrollTo` (sidebar only). Nothing on the mark path calls `go`
- **Spy runs with the sidebar hidden.** Cost = one rect read per heading per frame while scrolling. `ponytail:` comment in `toc.js` names the ceiling (thousands of headings) and the upgrade (`IntersectionObserver`)
- **Global names** stay specific: `tocCurrent`, `tocSpy`, `TOC_EDGE`

## Frozen contracts (W13)

```swift
// MarkedCore/TOC.swift (added)
extension TOC {
    /// Scroll-spy payload: integer ≥ -1. -1 → nil (no mark). Else throws TOCError.
    public static func current(_ raw: Any?) throws -> Int?   // stub: nil
}

// Marked/TOCSidebar.swift (added to TOCController)
@Published private(set) var current: Int?
func mark(_ i: Int?)                                          // stub: no-op

// Marked/WebView.swift
final class TOCMessages: NSObject, WKScriptMessageHandler {   // weak var coordinator
    func userContentController(_:didReceive:)                 // → coordinator?.tocMessage(message.body)
}
```

```js
// Resources/js/toc.js (added). Pure, exported for node behind the `typeof module` guard:
//   tocCurrent({tops: number[], height: number, atEnd: boolean}, edge = TOC_EDGE /* 8 */) -> int   // -1 when none
//   tocSpy(read: () => {tops, height, atEnd}, post: (int) => void) -> {update(), reset()}
// App world: scroll + ResizeObserver(#content) → rAF gate → spy.update(); hook("position", tocSpyReset)
```

## File ownership

| File | Owner |
|---|---|
| Stubs above; handler registration line; spike result | W13 (frozen after) |
| `Sources/MarkedCore/TOC.swift` (`current` body), `Tests/MarkedCoreTests/TOCTests.swift` (added cases) | K1 |
| `Resources/js/toc.js` (spy body + wiring), `Tests/js/toc.test.mjs` (added cases) | K2 |
| `Sources/Marked/TOCSidebar.swift` (mark + row look + keep visible), `WebView.swift` (`tocMessage`, handler body) | K3 |

## Tasks

### W13 — stubs + spike (sequential, main loop)

- [ ] W13.1 Branch `s13-scrollspy` from `s10-s13-design`
- [ ] W13.2 Stubs per "Frozen contracts"; register `TOCMessages` on the config (design.md S13 rule already updated with this plan)
- [ ] W13.3 Spike (temp env-guarded harness, not committed): a temporary line in the `toc.js` app block posts `postMessage(-1)` once at load and once from a `position` hook; `tocMessage` logs each receipt with `Thread.isMainThread`. Check: (a) both posts arrive, on the main thread; (b) `typeof window.webkit?.messageHandlers?.toc` is `"object"` via `callAsyncJavaScript` in `.defaultClient`; (c) the same expression in the page world (`evaluateJavaScript` without a content world, if it runs with page JS off) is not `"object"`, else record "page world not observable". (a) or (b) fails → stop and report to the user (no fallback is pre-approved; polling would change the design)
- [ ] W13.4 Remove the spike lines; `make test` + `make app` green, no warnings → commit

### K1 — TOC.current (builder)

- [ ] K1.1 Tests first (`TOCTests.swift`, no `import Foundation`):
  - `0` → `0`; `7` → `7`; `-1` → `nil`
  - throws `TOCError`: `-2`; `1.5`; `"1"`; `nil`; `[1]`; `["i": 1]`
- [ ] K1.2 Implement (`as? Int` on the bridged `NSNumber`; `Double` 1.5 fails the cast)

### K2 — toc.js spy (builder)

- [ ] K2.1 Node tests first (`toc.test.mjs`, same `createRequire`):
  - `tocCurrent` with `atEnd: false`, `height: 700` (tops listed): `[]` → `-1`; `[20, 500]` → `-1`; `[8, 500]` → `0` (edge inclusive); `[9]` → `-1`; `[-300, 5, 400]` → `1`; `[-900, -300, -10]` → `2`; `[0, 0]` → `1` (last match wins); custom edge `([30], 40)` → `0`
  - bottom rule, `atEnd: true`, `height: 700`: `[-500, 300, 600]` → `2`; `[-500, 800]` → `0` (800 is below the viewport); `[-500, 700]` → `0` (`top < height`, strict); `[]` → `-1`; `[20, 300]` → `1` (no heading at the edge, still the last visible)
  - `tocSpy`: first `update()` posts even `-1`; same reading again → no post; tops change the answer → one post; tops change but answer same → no post; `reset()` with unchanged tops → posts again; posts are integers
  - existing S10 tests unchanged and green
- [ ] K2.2 Implement pure functions; app-world wiring (`html` = `document.documentElement`): `const spy = tocSpy(() => ({ tops: [...content().querySelectorAll(TOC_SELECTOR)].map((h) => h.getBoundingClientRect().top), height: innerHeight, atEnd: html.scrollHeight > innerHeight && scrollY + innerHeight >= html.scrollHeight - 1 }), (i) => window.webkit?.messageHandlers?.toc?.postMessage(i))`; rAF gate; `addEventListener("scroll", gate, {passive: true})`; `new ResizeObserver(gate).observe(content())`; `Marked.hook("position", function tocSpyReset() { spy.reset() })`; `ponytail:` cost comment
- [ ] K2.3 `node --test 'Tests/js/*.test.mjs'` green

### K3 — app (builder)

- [ ] K3.1 `TOCController.mark` sets `current`. `TOCSidebar`: `ScrollViewReader`, `.id(i)` per row, current-row look and `onChange` scroll per "Own decisions"; mark only when `i < entries.count`
- [ ] K3.2 `TOCMessages.userContentController(_:didReceive:)` → `coordinator?.tocMessage(message.body)`; `Coordinator.tocMessage` per "Own decisions". No change to `refreshTOC`, `go`, the ready gate, or `decidePolicyFor`
- [ ] K3.3 `make app` builds, no warnings; `make test` green

### I13 — integrate + live check (sequential, main loop)

- [ ] I13.1 Merge K1–K3; `make test`
- [ ] I13.2 Fixture `spy dir/a.md` (space in path): `# One` at the top; `## Two` … `## Five` each after 40 filler paragraphs; `## Six` followed by 3 lines only (short last section); a Mermaid block between Three and Four; a second fixture with 80 `##` headings and 5 lines between each (sidebar keep-visible). Temporary env-guarded harness (not committed); it scrolls with `callAsyncJavaScript("window.scrollTo(0, y)")`, reads `TOCController.current`, counts `tocMessage` calls, and polls ≤ 500 ms per step:
  - scrollY 0 → `current == nil` (`# One` sits at the `#content` padding, top ≈ 32 px > 8)
  - indexes: One 0, Two 1, Three 2, Four 3, Five 4, Six 5. Scroll so `## Three` top = 0 → `2`; its top = +20 px (below the edge) → `1`; scroll to the end (Six never reaches the edge) → `5` (bottom rule); 1 screen up from the end → `4`
  - `TOCController.go(4)` (click path) → `current == 4`; page `Marked.token` unchanged
  - throttle: 50 `scrollTo` steps across Two…Four in one JS call → posts ≤ 3 (only changes)
  - live reload: insert `## Zero` before `## Two` while `## Three` is at the top → `current` becomes the new index of Three (`3`) with no user scroll; entries refresh; the marked row is the `Three` row
  - replace with headingless text → `current == nil`, "No headings"; restore → mark returns after one scroll
  - one-screen doc (`# A`, `## B`, 2 lines) → `current == nil` at load (no `atEnd` when the page cannot scroll)
  - style switch (`@AppStorage("style")` sans → mono) at a scroll position where a heading crosses the edge → `current` updates with no scroll call (ResizeObserver path); window resize (`setFrame`) likewise
  - two windows (two fixtures): scrolling one leaves the other's `current` unchanged
  - 80-heading fixture, sidebar open: scroll page to bottom → the sidebar `NSTableView` `rows(in: visibleRect)` contains the current row; scroll one heading further → sidebar scroll offset changes by less than one screen (no recenter jump)
  - retain: harness keeps a `weak` ref to a window's coordinator, closes the window, spins the run loop 1 s → ref is `nil`
  - ≥ 2 s between launches; `--args -ApplePersistenceIgnoreState YES`; pick window by `webView.url?.path`; menu keys via `NSApp.mainMenu.performKeyEquivalent` (posted keys stall when the app is not frontmost, S10)
- [ ] I13.3 Manual (person at the keyboard): trackpad-scroll a long doc with the sidebar open → mark follows smoothly, no flicker; click a row → jump + mark; sidebar does not fight a manual sidebar scroll while the page is still
- [ ] I13.4 Remove harness (`git checkout Sources/Marked/AppDelegate.swift`, delete `Harness.swift`); code-reviewer loop until clean (max 5) → `design/s13-review.md`; tick S13 in `design.md`; commit on `s13-scrollspy`

## Merge conflicts

- C3 coordinator: `tocMessage` + handler registration. No slice runs in parallel with S13, so no merge cost beyond what `estimates.md` counts

## Deferred

- `IntersectionObserver` instead of rect reads (only if a measured doc is slow)

## Unresolved questions

None. Resolved 2026-10-09:

1. ~~Short last section bottom rule?~~ Yes, in S13 (user, D47)
2. ~~Spike W13.3 failure?~~ Stop and ask; no pre-approved fallback (user, D48)
