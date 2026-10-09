# S13 review — TOC scroll-spy

Branch `s13-scrollspy` off `s10-s13-design` @ `29cdd70`. Tests: 136 Swift + 91 JS green (was 134 + 88: +2 Swift `TOC.current` tests, +3 JS spy tests). Built and checked by one fork, K1–K3 sequential.

## Spike W13.3

- (a) ✅ posts arrive on the main thread (`post body=2 main=true`)
- (b) ✅ `typeof window.webkit?.messageHandlers?.toc` = `"object"` in `.defaultClient`
- (c) page world sees `undefined` (handler not exposed there)
- `WKScriptMessageHandler.userContentController(_:didReceive:)` is `@MainActor` in this SDK: builds without `assumeIsolated`

## Live check (temp env-guarded harness, removed) — 34 pass, 0 fail

Fixtures (`spy dir/{a,b,c}`): 6 headings + mermaid + short last section; 80 headings; one-screen doc.

- Rule: top → nil; Three at 0 → 2; Three at +20 → 1; end → 5 (bottom rule); one screen up → 4
- Click path: `go(1)` → 1, `go(4)` → 4, no reload (`Marked.token` same)
- Throttle: 50 `scrollTo` in one JS turn → 1 post
- Reload (real S1 scroll to the inserted block): entries 7, `current` == ground truth (0); renumbering: Three scrolled to top → 3
- Headingless → nil + "No headings"; restore → mark back; one-screen doc → nil at load
- Style switch sans → mono: 2 → 1 == truth (ResizeObserver path); width resize == truth; height-only resize at the end: 5 → 4, `scrollY` unchanged (`resize` path)
- Windows independent; JS `true` post → `TOCError` logged, mark unchanged
- Sidebar (80 headings): end → row 79 visible; heading 40 → 41 moves the sidebar < one screen (dy 0); mark before rows (20 entries → `tocMessage(79)` → 80 entries) → row 79 visible after the refresh
- Retain: a content controller holding `TOCMessages` does not keep the coordinator alive (direct check). A closed document window object itself stays alive in AppKit (`window=true visible=false`), so the coordinator lives with it; pre-existing, not S13

## Code review

Round 1: 0 Critical, 0 Major, 1 Minor, 1 Cosmetic — both fixed.

- Minor: `TOCMessages` doc claimed a closed window frees its coordinator; live check disproved it (window kept by AppKit) → reworded to what the weak ref guarantees
- Cosmetic: `TOCError` `public var` fields only for defaults → `let` + explicit init with defaults; message now names the source (`toc spy post returned x; expected an integer ≥ -1`, tested)
Round 2: clean.

## Deviations from plan

- No `make install` (parallel-run guard); installed app unchanged
- Harness replaced the `toc` handler with a counting one on two windows (same coordinator path) to count posts; the third window kept the real `TOCMessages`
- Retain check: window-close variant not observable (AppKit keeps the window) → direct controller/handler check instead
- `TOCError` gained `source`/`expected` (message was `headings`-specific)

## Manual (I13.3, person at the keyboard)

- Trackpad-scroll a long doc with the sidebar open → mark follows, no flicker
- Click a row → jump + mark
- Scroll the sidebar by hand while the page is still → the sidebar does not snap back
