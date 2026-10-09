# S0 code review — round 1

Branch `s0-skeleton`, `eb42f24..776ef1a`. Date 2026-10-09.

## Overview

Change type: net new. Problems: 0 Critical, 1 Major, 8 Minor, 2 Cosmetic. The code agrees with the plan and the tests pass (19). Fix the S6 navigation rule in the design before S6 starts: a `<meta http-equiv="refresh">` in a hostile file must not open the browser. Fix the shared magic strings and the bridge error handling in S0 now.

---

## Major

### M1 Design: S6 web-link rule fires on non-click navigations — `design/design.md` S6 navigation rules

Fault: the rule "`http`, `https`, `mailto` → `NSWorkspace.shared.open`" does not check `navigationType`. A `.md` file with `<meta http-equiv="refresh" content="0;url=https://evil.example">` makes a navigation of type `.other`. Under S6 this opens the browser with no click. S0 is safe today: it cancels all such navigations.

Show: fixture with the meta refresh; after S6, the browser opens on file load.

Fixes:

- In S6, act only when `navigationType == .linkActivated`; cancel every other external navigation.

## Minor

### m1 Bridge failure subtitle is cleared only on `ok` — `Sources/Marked/WebView.swift` (send closure)

Fault: after a bridge failure, a later render with `ok: false` (a hook error) leaves "Render failed" in the subtitle, but the bridge works again. The subtitle reports bridge state, not hook state.

Fixes:

- Clear the subtitle when the result decodes, whatever `ok` is.

### m2 Decode failure gives an unclear error — `Sources/Marked/WebView.swift`

Fault: `CocoaError(.coderReadCorrupt)` prints a generic Cocoa message. The log does not say what was received or expected (`references/errors.md`).

Fixes:

- Throw `BridgeError.badResult(String(describing: raw))` with a description "Marked.render returned <raw>; expected {ok, errors}". Show `localizedDescription`-style text in the subtitle.

### m3 Magic strings duplicated across files — `SchemeHandler.swift`, `DocURL.swift`, `WebView.swift`

Fault: `"__marked__.html"`, `"marked"`, `"app"`, `"doc"` appear in more than one file (incidental coupling). A rename in one file breaks the shell load with no compile error.

Fixes:

- Put `DocURL.scheme`, `DocURL.appHost`, `DocURL.docHost`, `DocURL.shellName` in `DocURL`; use them in `SchemeHandler` and `WebView`.

### m4 Missing bundle resource fails silent — `WebView.resource`, `SchemeHandler`

Fault: a missing `marked.js` gives `""`; a missing `shell.html` or `base.css` gives a 403. The window shows a blank page with no cause.

Fixes:

- `preconditionFailure("Marked.app is missing Resources/<name>")` at load. A missing resource is a broken bundle, not a runtime state.

### m5 Implicitly unwrapped `queue` — `WebView.Coordinator`

Fault: `RenderQueue!` crashes if a delegate callback comes before `start`. The order holds today, but nothing enforces it (temporal coupling).

Fixes:

- `private var queue: RenderQueue?` and `queue?.` at each call site.

### m6 Document path can leak in a Referer header — `Resources/shell.html`

Fault: the page URL holds the absolute file path (`marked://doc/Users/<name>/…`). Remote `https:` images may receive it as a Referer. Not proven for a custom scheme origin; the fix is one line.

Fixes:

- Add `<meta name="referrer" content="no-referrer">` to the shell.

### m7 `MarkdownDocument.data` is not used — `Sources/Marked/MarkdownDocument.swift`

Fault: `FileWatcher` does every read (design), so the stored bytes are dead state.

Fixes:

- Remove the property; keep `init` non-throwing.

### m8 Test gap: `filePath` with a foreign scheme — `Tests/MarkedCoreTests/DocURLTests.swift`

Fault: no test shows `filePath(from: https://doc/x)` returns `nil`. The guard checks both scheme and host; only the host branch has a test.

Fixes:

- Add one assertion.

## Cosmetic

### c1 Redundant smoke test — `Tests/MarkedCoreTests/SmokeTests.swift`

Fault: W0 placeholder; real suites now cover `MarkedCore`.

Fixes:

- Delete the file.

### c2 Wire contract named on the JS side only — `WebView.swift` decode

Fault: the Swift decode does not point to the contract in `marked.js`.

Fixes:

- One-line comment at the decode: "Contract: see Resources/marked.js header."

## Coupling and design notes (no change in S0)

- `Coordinator.start` joins file read, queue setup, and shell load. S1 adds polling; S1 moves read + submit behind `FileWatcher` and gives the coordinator only `queue.submit`. Recorded in the S0 plan handoff.

## Checked, no problem

- Performance: one synchronous read per open; render on the main actor (cmark is fast); no loops over large data.
- Security: page JS off; CSP blocks frame, object, form, base (frame confirmed by smoke run); all non-shell navigations cancelled; handler serves two fixed resources only; dependency pinned by revision.
- Concurrency: `RenderQueue` generation check verified by red/green tests; stale completions do not mutate state.
- `marked.js`: errors use `textContent`; `render` never rejects (checked by node test and smoke run).

---

# Round 2 (after fixes)

All round-1 findings fixed: M1 (design S6 rule now requires `.linkActivated`), m1–m8, c1, c2. Integration probes re-run after the fixes: render, referrer meta, anchor scroll without reload, single `didFinish` all pass. 18 tests green, no build warnings.

New: 1 Cosmetic, fixed — `BridgeError` printed `Optional(...)`; now prints the bare value or `nil`.

Result: clean. Loop closed at round 2.
