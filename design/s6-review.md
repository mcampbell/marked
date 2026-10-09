# S6 code review — rounds 1-2

Branch `s6-links`, `s5-mermaid..HEAD`. Date 2026-10-09.

## Overview

Change type: patch (extends S0's single `decidePolicyFor`) plus net-new modules (`LinkPolicy`, `js/anchors.js`). Round 1: 0 Critical, 0 Major, 1 Minor, 0 Cosmetic, fixed. Round 2: clean. All link rules sit in one pure, table-tested function. The app layer only maps actions to effects. 126 Swift + 48 JS tests and the I6 live check (22/22) pass.

---

## Minor

### m1 The link effect runs before WebKit gets its answer — `Sources/Marked/WebView.swift` `decidePolicyFor`

Fault: `performLink` ran before `decisionHandler`. A reveal of a missing file calls `NSApp.presentError`, which runs an app-modal alert inside WebKit's policy callback. The navigation decision then waits until the user closes the alert (the I6 harness showed that an app-modal alert blocks the main actor).

Fixes:
- Call `decisionHandler` first, then `performLink`. **Fixed.** The I6 re-run passes 22/22, including the missing-file alert.

## Checked, no change

- Security (`mc-code-security`, hostile `.md`):
  - A non-click navigation is always cancelled (rule 2), whatever its scheme, so a meta refresh does nothing (live check).
  - Local non-Markdown targets (`.app`, scripts) are only revealed in Finder, never opened.
  - `file:`, `javascript:`, `data:` and `marked://app/…` are cancelled.
  - `.md` targets open as read-only documents in this app.
  - CSP `form-action 'none'` and `frame-src 'none'` stop forms and frames before a policy call.
  - Schemes are compared in lowercase (test).
- Purity: `LinkPolicy.decide` reads nothing from the disk. `URL(fileURLWithPath:isDirectory: false)` avoids the directory probe that would make the tests depend on the machine.
- Heading ids: the slugger loops over **all** used ids (collision tests: `Intro, Intro-1, Intro` and the reserved `intro-1`). It uses the upstream character set `\p{Alphabetic}\p{M}\p{Nd}\p{Nl}\p{Pc}`, `-`, space, and does not trim. Ids that a heading already has are reserved first. The global names are specific (`slugger`, `SLUG_STRIP`, `addHeadingIds`).
- `target="_blank"`: WebKit asks `decidePolicyFor` first, so no `WKUIDelegate` is needed (live check).
- Logging: one `NSLog` line per effect (action and URL). The open errors go to the system alert, and the log keeps the URL.
