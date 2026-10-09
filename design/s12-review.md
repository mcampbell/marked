# S12 review — print

Branch `s12-print` off `s10-s13-design` @ `478caa1`. Tests: 126 Swift + 64 JS green. Live check: temp env-guarded harness (removed), fixture with frontmatter, `mark`, image, 3×40 filler paragraphs, unbroken 300-char token + `ENDOFLINE`, 80-row table, mermaid, find bar open on `filler` (120 hits).

## Spikes

- p1 ✅ harness PDF via the shipped print config, `jobDisposition = .save`: 12 pages, text selectable, first + last heading present. Without `op.view?.frame = web.bounds`: identical (12 pages, same byte size) → line dropped
- p2 ✅ posted Cmd-P → `NSPanel` sheet attached to the document window. While the sheet is key, `NSApp.keyWindow` is the panel → `WebView.webView(in:)` nil → a second Cmd-P is a no-op. "Save as PDF" button itself: manual (P3.4)
- p3 ✅ mermaid flowchart drawn on the last page
- p4 ✅ exactly one `Print…` item, enabled, Cmd-P; no Page Setup item

## PDF checks

- Text (PDFKit): headings, `ENDOFLINE`, `marked`, frontmatter present; no file name, date, or "n of m" → no header/footer
- Pages (rasterized, read): full-width text in default margins; `X…ENDOFLINE` wraps to 6 lines inside the `pre` box; `pre`, frontmatter, `mark` backgrounds print; find hits not colored; no heading alone at a page bottom; table row text never split

## Code review (code-reviewer, 2 rounds)

Round 1: 0 Critical, 0 Major, 2 Minor, 0 Cosmetic. Round 2: clean.

- Minor (fixed) print state (`weak var web`, `makePrintOperation`, `print`) braided into the coordinator, which already owns render/find/style/links. Print needs only the web view → `WebView.webView(in:)` (the existing walk) + `WKWebView.makePrintOperation()` / `printAsSheet()`; `findController(in:)` builds on `webView(in:)`. Deviation from the plan's frozen `coordinator(in:)` / `Coordinator.print()` contract; no builders depended on it
- Minor (fixed) `.find-hit, .find-current` print rule dead: `find.js` uses only `CSS.highlights`. Dropped; pages re-checked, hits still not colored
- Security (`mc-code-security` lens): no new load path, no new scheme route; print reads only the rendered DOM. No finding

## Known limits

- WebKit leaves an empty sliver of the next table row's borders at a page bottom (row text moves whole to the next page). `td, th { break-inside: avoid }` tried: no change. Cosmetic, accepted
- `break-after: avoid` on headings: no stranded heading seen in the fixture; WebKit support not otherwise proven

## Not done here

- P3.4 manual (person at keyboard): Cmd-P → PDF ▸ Save as PDF → Preview; Cmd-P with only the Open dialog showing → nothing
- `make install` skipped (parallel slices share `~/Applications`); main loop installs after merge
- R3 (printed syntax colors): S11 not on this base; whoever lands second runs it
