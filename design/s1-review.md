# S1 code review — round 1

Branch `s1-live`, `0323a78..23eaa3b`. Date 2026-10-09.

## Overview

Change type: patch (extends the S0 design: frozen render lifecycle, hook phases, resource helper). Problems: 0 Critical, 1 Major, 2 Minor, 1 Cosmetic. The code fits the S0 contracts. 43 Swift + 6 JS tests pass; live checks pass. Fix the scroll hook: a bad `data-sourcepos` from raw HTML throws on every render.

---

## Major

### M1 Malformed `data-sourcepos` throws in the scroll hook — `Resources/js/scroll.js`

Fault: raw HTML (allowed, Q8) can carry `data-sourcepos="x"`. The regex returns `null`; `m[1]` throws. Every later render shows a red `render-error` box ("scrollToChange: …"). The attribute is untrusted document input.

Show: `<div data-sourcepos="x">a</div>` in a document, then edit the file.

Fixes:
- Pure `rangeOf(sourcepos)` returns `null` for a bad value; the hook drops those elements. Node tests pin both cases. **Fixed.**

## Minor

### m1 Poll timer stops while a menu is open or the window resizes — `Sources/Marked/FileWatcher.swift`

Fault: `Timer.scheduledTimer` runs only in the run loop's default mode. Event tracking (menus, live resize) pauses it, so a save is not shown until the tracking ends.

Fixes:
- Add the timer to `RunLoop.main` in `.common` modes. **Fixed.**

### m2 Bare-CR line endings give a wrong scroll target — `Sources/MarkedCore/LineDiff.swift`

Fault: cmark counts a lone `\r` as a line break; `LineDiff` splits on LF only. A classic-Mac (CR-only) file maps the change to line 1.

Fixes:
- Deferred: CR-only files are rare. Recorded in `design.md` Deferred. If needed later, split on CR, LF, and CRLF the same way cmark does.

## Cosmetic

### c1 `hasRendered` is set at submit, not at render — `Sources/Marked/WebView.swift`

Fault: the banner suffix "showing the last good version" can appear a few milliseconds before the first render lands.

Fixes:
- Won't change: the text is true a moment later, and the window is not readable in that gap.

## Checked, no problem

- Coupling: the watcher reducer is pure and has no Foundation dependency; the app shell only probes and forwards. The read moved out of `Coordinator.start` (S0 review note) — done.
- Correctness: retry while an error is outstanding, 2-poll missing grace, banner message de-duplication — all pinned by tests and the live run.
- Concurrency: the timer captures `[weak self]`; `dismantleNSView` stops it. A close-window run is not verified (needs GUI scripting).
- Security: no new scheme or navigation surface; the only new input is `data-sourcepos` (M1).
- Performance: one `stat` per window per 0.5s; the read happens only on a stamp change or an outstanding error.

---

# Round 2 (after fixes)

M1 and m1 fixed; m2 deferred with a design note; c1 no change. Tests: 43 Swift + 8 JS green. Live checks re-run after the fixes. Result: clean.
