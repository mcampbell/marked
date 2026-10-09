# S10 code review — rounds 1-2

Branch `s10-toc`, `478caa1..HEAD`. Date 2026-10-09.

## Overview

Change type: patch (TOC sidebar on the existing render lifecycle). Round 1: 0 Critical, 0 Major, 2 Minor, 0 Cosmetic, both fixed. Round 2: clean. The sidebar lists every heading after each render, and a click scrolls by index. Find, banner, live scroll, and the window subtitle still work with the sidebar open. 132 Swift + 70 JS tests and the I10 live check (24/24, plus 2/2 subtitle) pass.

---

## Minor

### m1 Window subtitle moved into the detail column — `Sources/Marked/ReaderView.swift`

Fault: `.navigationSubtitle` stayed on the `WebView` chain, which is now the split view's detail column. Before S10 it sat on the window root. No check showed that render and style failures still reach the window subtitle.

Fixes:

- Move the modifier to the outer `NavigationSplitView`. **Fixed.** Live check: `setFailure("X")` → each window's `subtitle == "Render failed: X"` (2/2).

### m2 Strong `web` capture in `refreshTOC` — `Sources/Marked/WebView.swift`

Fault: the refresh `Task` held the `WKWebView` strongly. Every other bridge closure captures it `weak`. A closed window kept its web view until the JS call returned.

Fixes:

- `Task { [weak self, weak web] in guard let web else { return } … }`. **Fixed.**

## Checked, no change

- Stale replies: each refresh bumps `tocGeneration`; an older reply is dropped. Shell reload re-renders through `onRendered` (live check: entries repopulate).
- Index safety: `tocGo` accepts only an integer in range (node tests: `-1`, `3`, `1.5`, `"0"`, `NaN`, null root). Swift `TOC.parse` rejects any payload except levels 1–6 with string text (10 bad payloads tested).
- Security: heading text renders through SwiftUI `Text`, never as markup. No new message channel; Swift only reads the return value of `callAsyncJavaScript` in `.defaultClient`.
- Click rule: one `Button` per row, no `List(selection:)`, so S13 can mark a row without a scroll.
- Performance: one `querySelectorAll` per render, O(headings).
- Spike W10.3: pass, no fallback (see plan).
