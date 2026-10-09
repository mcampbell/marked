# S3 code review — rounds 1-2

Branch `s3-find`, `s9-windows..HEAD`. Date 2026-10-09.

## Overview

Change type: net new (find) plus a patch (`RenderQueue.onRendered`, `WebView` bridge, app commands). Round 1: 0 Critical, 1 Major, 2 Minor, 1 Cosmetic, all fixed. Round 2 (the fixes): clean. The most important point: range lookup was O(matches × text nodes), so a one-letter query could stall a large page. 120 Swift + 25 JS tests and the live checks pass.

---

## Major

### M1 Range lookup scans every text node for each match — `Resources/js/find.js`

Fault: `locate()` scanned the node list backwards for each match offset, so the cost was O(matches × nodes). A one-letter query in a long document gives tens of thousands of matches over thousands of nodes, and the page freezes while the user types.

Fixes:
- The offsets arrive in ascending order, so a pure `locator(starts)` uses one forward pointer: O(nodes + matches). It is exported and has a node test that covers the boundary rules (an end at a boundary stays in the earlier node, a start goes to the last node there, empty nodes). **Fixed.** The live re-check confirms each range text (`needle in` ×5, `**nee**dle split`).

## Minor

### m1 The coordinator holds the session twice — `Sources/Marked/WebView.swift`

Fault: `Coordinator` kept a strong `find: FindSession` and a weak `findController` (which owns the same session). There were two ways to reach one object.

Fixes:
- Remove `find`. The terminate path uses `findController?.session`. **Fixed.** The live re-check confirms that the shell reload restores "3 of 6" (JS state `6/2`).

### m2 Stale comment on the Ctrl-F monitor — `Sources/Marked/MarkedApp.swift`

Fault: the comment said "focused scene" after the switch to the key-window lookup.

Fixes:
- The comment now states why: one Find path, and a SwiftUI menu item takes one shortcut. **Fixed.**

## Cosmetic

### c1 `focusRequest` declared after `init` — `Sources/Marked/FindController.swift`

Fixes:
- Moved it next to the other published properties. **Fixed.**

## Checked, no change

- Coupling: `FindCommands` → `WebView.findController(in:)` → `navigationDelegate as? Coordinator` is control coupling to the view tree. It replaces `@FocusedValue` / `@FocusedObject`, which stayed nil in this `DocumentGroup` (live check, I3.2). Keep it. Go back to a focused value if a later SwiftUI version publishes it.
- Ordering: the revision rule drops stale results. `close()` and `shellWillReload()` bump the revision. JS applies calls in order, so a `.state` after a render reflects any earlier `.set`/`.step`. 11 `FindTests` pin this.
- Readiness: `onRendered` fires only for a current-generation success, after `lastRendered` updates (3 queue tests). A render from the old shell cannot mark the new shell as ready.
- Errors: the bridge logs `Marked.find.<call> returned <raw>; expected {count, index}` and rethrows. The session shows "Find failed" and keeps the last good status, so a failure never shows as "No results".
- Security: the query goes in through `arguments:`, not string concatenation. Regex metacharacters are escaped, and the pattern is literal parts joined by `\s+`, with no nested quantifiers (no ReDoS). The highlights do not change the DOM (`innerHTML` is unchanged).
- During the async hook phases, a `step` call can see Ranges that the render collapsed. `decorate` rebuilds them, and the Swift `.state` after the render corrects the label. This is harmless.
- Ctrl-F also fires inside the find field, where the Emacs binding moves the cursor forward one character. The plan requires Ctrl-F. Accepted.

## Not verified (needs a person at the keyboard, I3.3)

- Shift-Return → previous, and Esc → close, inside the `TextField`. The field editor can consume them before `onKeyPress`.
- Real Cmd-F / Ctrl-F keystrokes. Synthetic `NSEvent`s pass. `CGEvent.postToPid` did not deliver, and System Events keystrokes need Accessibility, which this machine does not allow.
