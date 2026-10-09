# S2 code review — round 1

Branch `s2-styles`, `0478594..8341d1b`. Date 2026-10-09.

## Overview

Change type: patch (extends `RenderQueue`, the coordinator, and the app commands inside the S0/S1 contracts). Problems: 0 Critical, 0 Major, 1 Minor, 1 Cosmetic. Style switching works across windows with no reload; the shared in-flight slot keeps "style then render" and the generation rules. 106 Swift + 12 JS tests and the live checks pass.

---

## Minor

### m1 `apply` marks a style as requested even when the queue does not exist — `Sources/Marked/WebView.swift`

Fault: `lastStyle` is set before `queue?.setStyle`. A call before `start` would record the style but never send it, and later calls with the same style would be skipped (temporal coupling). Today `makeNSView` calls `start` first, so it does not fail; nothing enforces that order.

Fixes:
- `guard let queue, style != lastStyle` before recording. **Fixed.**

## Cosmetic

### c1 Stale "W2 stubs" comment — `Sources/MarkedCore/RenderQueue.swift`

Fixes:
- Replaced with a one-line why. **Fixed.**

## Checked, no change

- Correctness: shared slot, style first, stale completions discarded, newer style kept after a failed or successful older send, separate style failure path — all pinned by 13 queue tests; live run E confirmed a style failure survives a successful render and clears on the next applied style.
- Persistence and scope: one `@AppStorage("style")`; live runs A (no value → sans), B (`-style serif`), C (two windows switch together, same page token, `scrollY` kept), D (relaunch keeps mono).
- Code and frontmatter: stay `ui-monospace` in every style (live runs).
- Security: style CSS comes only from the app bundle; no new input surface.
- Performance: one small file read per style change.

## Not verified by automation

- Cmd-1/2/3 key presses and the View-menu check marks (needs a person at the keyboard; Accessibility permission would be required to script it).

---

# Round 2 (after fixes)

m1 and c1 fixed. 106 Swift + 12 JS tests green, build warning-free. Result: clean.
