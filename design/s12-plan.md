# S12 implementation plan — print (PDF via print panel)

Source: `design.md` (S12 row, "S12 print rules", R3, C1, C3, C5), `grill.md` D39, D43, D44, D45. Size: 2 pts (`estimates.md`). Builds on `main` (@ `316a1a1`, S0–S8). Runs parallel with S10, S11.

Done = File > Print… (Cmd-P) in a document window opens the system print panel as a sheet on that window; the panel's "Save as PDF" writes a multi-page PDF with selectable text; pages show the current style font at full paper width, code/`mark`/table backgrounds printed, long code lines wrapped, mermaid diagrams drawn, no header/footer/page numbers, no break inside a code block/diagram/table row/image, headings kept with the next block, find highlights not printed; Cmd-P with no document window does nothing; there is exactly one Print item and it is enabled; `make test` green; live check passes.

## Shape

```
P1 spikes p1–p4 (gate; sequential, main loop)
P2 @media print CSS (main loop)
P3 live check: harness PDF + rasterized pages (main loop)
P4 review + commit
```

No builders: the slice is ~30 lines of Swift and ~10 lines of CSS, and the spikes write most of the Swift. Spawning K-stream worktrees costs more than it saves.

## Own decisions

- **Lookup helper.** Extract the `WKWebView` walk inside `WebView.findController(in:)` into `@MainActor static func coordinator(in window: NSWindow?) -> Coordinator?`. `findController(in:)` becomes `coordinator(in: window)?.findController`. Print uses the same helper. One walk, two callers
- **Coordinator keeps the web view.** `private weak var web: WKWebView?`, set in `start(_:…)`. `print()` reads `web?.window`; nil web or nil window → return (no-op)
- **One builder, two runners.** `func makePrintOperation() -> NSPrintOperation?` holds all print config; `print()` = `makePrintOperation()` + `op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)`. The live-check harness calls the same `makePrintOperation()` and only changes the job disposition, so the check exercises the shipped config
- **Print config.** `let info = NSPrintInfo.shared.copy() as! NSPrintInfo`; `info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false` (SDK: `NSPrintHeaderAndFooter` is a dictionary key, not a property; design.md's `headerAndFooter = false` means this); default margins; `info.isVerticallyCentered = false`; `web.printOperation(with: info)`; `op.view?.frame = web.bounds` (blank-page workaround, p1 confirms it is needed or drops it). `showsPrintPanel`/`showsProgressPanel` left at defaults (`true`)
- **Backgrounds.** `cfg.preferences.shouldPrintBackgrounds = true` in `makeNSView` (WKPreferences, macOS 13.3+; min target 14)
- **Command.** In `MarkedApp.commands`: `CommandGroup(replacing: .printItem) { Button("Print…") { WebView.coordinator(in: NSApp.keyWindow)?.print() }.keyboardShortcut("p") }`. Key window resolved at click time, like `FindCommands` (`@FocusedValue` stays nil here, S3). Keep any Page Setup item the system supplies; do not add one
- **Print = DOM at click time.** No render pause while the panel is open (design: accepted)
- **CSS.** `@media print` block appended to `base.css` (C5 with S11). Find highlights: both the Custom Highlight API names and the fallback classes, since `find.js` may use either. S1's flash is a 1.2 s Web Animation, not CSS: not handled
- **No new Swift test.** No pure logic: config and wiring only. The harness check is the test

## Frozen contracts

```swift
// Marked/WebView.swift
@MainActor static func coordinator(in window: NSWindow?) -> Coordinator?   // WKWebView walk, moved from findController(in:)
@MainActor static func findController(in window: NSWindow?) -> FindController?   // = coordinator(in:)?.findController

// Coordinator
func makePrintOperation() -> NSPrintOperation?   // nil when no web view / window
func print()                                     // makePrintOperation + runModal as a sheet
```

```css
/* base.css, appended */
@media print {
  #content { max-width: none; padding: 0 }
  pre { white-space: pre-wrap }
  pre, div.mermaid, tr, img { break-inside: avoid }
  h1, h2, h3, h4, h5, h6 { break-after: avoid }
  ::highlight(find-hit), ::highlight(find-current) { background: transparent }
  .find-hit, .find-current { background: transparent }
}
```

`pre { white-space: pre-wrap }` touches code only; the design rule "no `white-space: pre*` on body text" is unaffected.

## SDK facts (CLT SDK, `xcrun --show-sdk-path`, checked 2026-10-09)

- `WKWebView.h:587` `printOperationWithPrintInfo:` → Swift `printOperation(with:)`, macOS 11+
- `WKPreferences.h:58` `shouldPrintBackgrounds`, macOS 13.3+
- `NSPrintInfo.h:77` `NSPrintHeaderAndFooter` dictionary key (no property); `:64`/`:72`/`:85` `NSPrintJobDisposition`, `NSPrintJobSavingURL`, `NSPrintSaveJob`; `:127` `jobDisposition` property
- `NSPrintOperation.h:79–80` `showsPrintPanel`, `showsProgressPanel`; `:105` `runOperationModalForWindow:delegate:didRunSelector:contextInfo:`
- SwiftUI swiftinterface: `CommandGroupPlacement.printItem` exists
- Unconfirmed: whether `DocumentGroup(viewing:)` already ships a Print item (p4); whether `op.view?.frame` is needed (p1); WebKit print support for `break-after: avoid` on headings (P3 looks)

## Tasks

### P1 — spikes (gate, main loop)

- [ ] P1.1 Branch `s12-print` off `main`. Implement the frozen contracts (helper extract, `web` ref, `makePrintOperation`, `print`, `shouldPrintBackgrounds`, command). `make test` green, `make app` no warnings
- [ ] P1.2 Temporary env-guarded `Sources/Marked/Harness.swift` + one line in `AppDelegate.applicationDidFinishLaunching` (never committed; `git checkout` after). Harness, after first render: `let op = coordinator.makePrintOperation()`; `op.printInfo.jobDisposition = .save`; `op.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = <scratch>/out.pdf`; `op.showsPrintPanel = false`; `op.showsProgressPanel = false`; `op.runModal(for: window, …)`; wait for the file; log `PDF written`
- [ ] P1.3 p1 not blank + paginates: harness PDF of a 3+ screen fixture has `pageCount > 1` and its text contains the first and last heading (PDFKit script, see P3.2). Retry without `op.view?.frame = web.bounds`: keep the line only if dropping it breaks p1
- [ ] P1.4 p2 Save as PDF via the panel: harness launch 2 posts Cmd-P with `NSApp.postEvent` → log that a sheet is attached to the window (`window.attachedSheet != nil`), then `NSApp.endSheet` / cancel. The "PDF" button itself is a person step (P3.4)
- [ ] P1.5 p3 mermaid prints: fixture flowchart → rasterized page shows the diagram (P3.3)
- [ ] P1.6 p4 one Print item: harness logs every `NSApp.mainMenu` item titled `Print…` with `isEnabled` and key equivalent → exactly one, enabled, `p` + Cmd
- [ ] Gate: any of p1/p3/p4 fails → stop, record facts in this file, return to the user. No pre-approved fallback (`createPDF` gives one tall page, not pagination)

### P2 — print CSS (main loop)

- [ ] P2.1 Append the frozen `@media print` block to `base.css`

### P3 — live check (main loop)

- [ ] P3.1 Fixture dir in the scratchpad (path with a space): `p.md` with frontmatter, `h1`, 3 `h2`s each followed by 40 filler lines, a fence with a 300-char line ending in `ENDOFLINE`, an 80-row table, a mermaid flowchart, `==marked==` text, an image `img.png`. Harness opens the find bar with query `filler` before printing
- [ ] P3.2 PDF text check, `swift` script (scratchpad, not committed): `import PDFKit`; print `pageCount`; print whether `string` contains first heading, last heading, `ENDOFLINE` (wrap, not clipped), `marked`; print whether it contains `p.md` or a date string (header/footer must be absent). Expect `pageCount ≥ 3`, all true, header/footer false
- [ ] P3.3 Visual check: `sips -s format png out.pdf --out page1.png` (page 1) and a per-page split if needed (`PDFDocument.page(at:)` → `NSImage` → PNG in the same script). Main loop reads the PNGs: full-width text, `pre` gray background, `mark` yellow, no find-hit color on `filler`, mermaid drawn, no table row split, no heading alone at a page bottom, no header/footer
- [ ] P3.4 Manual (person at the keyboard): Cmd-P → panel sheet → PDF ▸ Save as PDF → open in Preview; matches P3.3. Cmd-P with no window (all closed, app still running if Open dialog shown) → nothing
- [ ] P3.5 Remove harness (`git checkout Sources/Marked/AppDelegate.swift`, delete `Harness.swift`); `make test`; `make install`

### P4 — review + commit

- [ ] P4.1 code-reviewer loop (+ `mc-code-security`: no new load path, print reads only the rendered DOM) until clean (max 5) → `design/s12-review.md`
- [ ] P4.2 Tick S12 in `design.md`; commit on `s12-print`

## R3 (second of S11/S12 to land)

Whoever lands second reruns P3.2–P3.3 with a fixture fence ` ```swift ` → rasterized page shows token colors and the `pre` background. If S11 lands second, it reuses this plan's harness steps P1.2 and P3.3.

## Merge conflicts

- C1 `MarkedApp.commands`: Print item (S10 adds `SidebarCommands`)
- C3 `WebView`: helper extract, `web` ref, `makePrintOperation`/`print`, one `shouldPrintBackgrounds` line (S10 TOC bridge)
- C5 `base.css`: `@media print` block appended at the end (S11 `.hljs` overrides). All counted in `estimates.md`

## Deferred

- Separate File > Export as PDF… item (design Deferred)
- A render landing while the print panel is open (accepted)

## Unresolved questions

None. Resolved 2026-10-09 (author, D46):
1. ~~`headerAndFooter` wording?~~ design.md now names the `NSPrintHeaderAndFooter` dictionary key (SDK: `NSPrintInfo.h:77`)
2. ~~Cmd-P with no document window?~~ Enabled, no-op (as designed)
