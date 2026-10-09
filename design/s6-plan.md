# S6 implementation plan — links

Source: `design.md` (S6 row, "S6 navigation rules"), `grill.md` Q9, D17, D18, D25, D31, S0 review M1. Size: 1 pt (`estimates.md`). Builds on `s5-mermaid`.

Done = a click on a web link (`http`, `https`, `mailto`, also `target="_blank"`) opens the default browser or mail app; a click on a local `.md`/`.markdown`/`.mdown` link opens it in its own window at the top (an open one is focused, D31); a click on another local file reveals it in Finder, never opens it; `#anchor` scrolls in place to a GitHub-slugger heading id; a missing target shows the system error alert; every non-click navigation (meta refresh) and every other scheme (`file:`, `javascript:`, `data:`, `marked://app/…`) is cancelled with no side effect; the shell still loads and reloads; `make test` green; live check passes.

## Shape

```
W6 frozen stubs (sequential, main loop)
 ├─ K1 LinkPolicy (MarkedCore) + tests          ┐
 ├─ K2 js/anchors.js slugger + hook + node tests │ parallel, disjoint files, one builder each, own worktree
 └─ K3 WebView coordinator: decide → perform     ┘
I6 integrate + live check (sequential, main loop)
```

Critical path: W6 → join(K1–K3) → I6. Expected longest: K1.

## Own decisions

- **One pure decision, in MarkedCore.** `LinkPolicy.decide(url, shell:, linkActivated:) -> LinkAction` holds every rule from `design.md` "S6 navigation rules", in order, first match wins. Fully unit-tested, no AppKit. The coordinator only maps the action to an effect and calls `decisionHandler` (`.allow` for `.allow`, `.cancel` for every other action)
- **Rules (frozen order):** (1) URL with the fragment removed equals the shell URL → `.allow` (first load, shell reload and `#anchor`, whatever the navigation type); (2) not `linkActivated` → `.cancel` (meta refresh, S0 review M1); (3) `http`/`https`/`mailto` → `.openExternal(url)`; (4) `marked://doc/<path>` with path extension `md`/`markdown`/`mdown` (case-insensitive; query and fragment ignored) → `.openDocument(fileURL)`; (5) other `marked://doc/<path>` whose last component is not `shellName` → `.reveal(fileURL)`; (6) anything else (`file:`, `javascript:`, `data:`, `marked://app/…`) → `.cancel`. Paths come from `DocURL.filePath` (percent-decoded), so spaces and `#` in names work
- **Effects (app layer):** `.openExternal` → `NSWorkspace.shared.open`; `.openDocument` → `NSDocumentController.shared.openDocument(withContentsOf:display: true)`, and on error → `NSApp.presentError`; `.reveal` → if the file exists `NSWorkspace.shared.activateFileViewerSelecting([url])`, else `NSApp.presentError(CocoaError(.fileNoSuchFile, …))`. Every effect except `.allow` is logged with `NSLog` (one line: action + URL)
- **Test seam:** `Coordinator.performLink: (LinkAction) -> Void` (default = the effects above). The I6 harness replaces it to record actions, so the live check opens no browser or Finder windows; it passes `.openDocument` through to prove a real window opens
- **`target="_blank"`:** WebKit still asks `decidePolicyFor` (with a nil target frame) before it asks the UI delegate for a new web view. The rules do not look at the target frame, so a `_blank` web link opens the browser. No `WKUIDelegate`. I6 checks this
- **Heading ids (`js/anchors.js`, `decorate` phase):** pure `slugger()` returns `slug(text)` per GitHub slugger: lowercase; remove every char that is not a Unicode letter, mark, number, connector punctuation (`_`), `-`, or space; each space → `-` (no collapse: "C++ & Go!" → `c--go`); repeats get `-1`, `-2`, …. The hook first reserves the ids of headings that already have one (raw HTML), then sets ids on the rest of `#content h1`–`h6` from `textContent`. Runs on every render
- **Anchor scroll:** `#x` → rule (1) `.allow` → WebKit scrolls in the same document (S0 spike d: no reload, `Marked` and find state survive)

## Frozen contracts (W6)

```swift
// MarkedCore/LinkPolicy.swift
public enum LinkAction: Equatable, Sendable {
    case allow, cancel
    case openExternal(URL), openDocument(URL), reveal(URL)   // file URLs for the last two
}
public enum LinkPolicy {
    public static func decide(_ url: URL, shell: URL, linkActivated: Bool) -> LinkAction   // stub: .allow for shell match, else .cancel (today's behavior)
}

// Marked/WebView.swift (Coordinator)
var performLink: (LinkAction) -> Void        // default: the effects in "Own decisions"
```

```js
// Resources/js/anchors.js (app world). Registers Marked.hook("decorate", addHeadingIds).
// Pure, exported for node behind the `typeof module` guard:
//   slugger() -> { slug(text) -> string, reserve(id) }   // one per render; repeats → -1, -2, …
```

## File ownership

| File | Owner |
|---|---|
| `LinkPolicy.swift` stub; `anchors.js` stub; `userScripts` line; `performLink` property (default no-op) + `decidePolicyFor` calling `LinkPolicy.decide` | W6 (frozen after) |
| `Sources/MarkedCore/LinkPolicy.swift` (body), `Tests/MarkedCoreTests/LinkPolicyTests.swift` | K1 |
| `Resources/js/anchors.js` (body), `Tests/js/anchors.test.mjs` | K2 |
| `Sources/Marked/WebView.swift` (`performLink` default effects) | K3 |

## Tasks

### W6 — stubs (sequential, main loop)

- [ ] W6.1 Branch `s6-links` from `s5-mermaid`
- [ ] W6.2 `LinkPolicy` stub keeping today's behavior (shell match → `.allow`, else `.cancel`); `decidePolicyFor` → `let a = LinkPolicy.decide(url, shell: shell, linkActivated: action.navigationType == .linkActivated)`; `if a != .allow && a != .cancel { performLink(a) }`; `decisionHandler(a == .allow ? .allow : .cancel)`; `performLink` default no-op. `anchors.js` stub (`slugger` returns the text unchanged, no hook); append `resource("anchors", "js", subdirectory: "js")` to `userScripts`
- [ ] W6.3 `make test` + `make app` green; app still renders (open one fixture) → commit → fork worktrees

### K1 — LinkPolicy (builder)

- [ ] K1.1 Tests first (no `import Foundation`; URLs via `.init(string:)!`), shell `marked://doc/Users/me/My%20Docs/__marked__.html`:
  - shell, shell + `#x`, both with `linkActivated` false and true → `.allow`
  - `https://e.com`, `http://e.com`, `mailto:a@b.c` + click → `.openExternal(same URL)`; same + not a click → `.cancel`
  - `marked://doc/Users/me/My%20Docs/b.md` + click → `.openDocument(file:///Users/me/My Docs/b.md)`; `B.MD`, `.markdown`, `.mdown`, `b.md#sec`, `b.md?x=1` → `.openDocument` without query or fragment; `sub%20dir/c.md` decodes the space; a `%23` in a name stays part of the path
  - `marked://doc/…/notes.txt`, `…/report.pdf`, `…/Tool.app` + click → `.reveal(file URL)`; not a click → `.cancel`
  - `file:///etc/hosts`, `javascript:alert(1)`, `data:text/html,x`, `marked://app/base.css` + click → `.cancel`
  - another directory's shell (`marked://doc/other/__marked__.html`) + click → `.cancel` (a shell file is never a target; reuse the `shellName` check)
- [ ] K1.2 Implement per "Rules (frozen order)", reusing `DocURL.filePath` and `DocURL.shellName`

### K2 — anchors.js (builder)

- [ ] K2.1 Node tests first (`Tests/js/anchors.test.mjs`): `Intro` → `intro`; second `Intro` → `intro-1`, third → `intro-2`; `C++ & Go!` → `c--go`; `Héllo Wörld` → `héllo-wörld`; `日本語 見出し` → `日本語-見出し`; `snake_case-ok` → `snake_case-ok`; `Trim me` → `trim-me` (GitHub trims); emoji dropped (`Ship 🚀 it` → `ship--it`); `reserve("intro")` then `Intro` → `intro-1`; empty heading → `""` then `-1` on repeat (as github-slugger)
- [ ] K2.2 Implement `slugger` (module-level regex with the `u` flag)
- [ ] K2.3 `decorate` hook `addHeadingIds`: one `slugger()` per render; reserve existing `id`s on `#content h1…h6` first; then set `id = slug(textContent)` where missing and the slug is non-empty
- [ ] K2.4 `node --test 'Tests/js/*.test.mjs'` green

### K3 — coordinator effects (builder)

- [ ] K3.1 `performLink` default per "Effects (app layer)": `NSWorkspace.shared.open`, `NSDocumentController.shared.openDocument(withContentsOf:display: true) { _, _, error in if let error { NSApp.presentError(error) } }`, reveal with an existence check, `NSLog` per action. No change to `didFinish`, the ready gate, the terminate path, or rule order (all in `LinkPolicy`)
- [ ] K3.2 `make app` builds, no warnings; `make test` green

### I6 — integrate + live check (sequential, main loop)

- [ ] I6.1 Merge K1–K3; `make test`; `make install`
- [ ] I6.2 Fixture dir with a space in its name: `a.md` (headings `Intro`, `Intro`, `C++ & Go!`, raw `<h2 id="custom">Custom</h2>`, 60 filler paragraphs between them; links `#intro-1`, `#c--go`, `#custom`, `b.md`, `b.md#x`, `sub dir/c.md`, `missing.md`, `notes.txt`, `https://example.com`, `mailto:a@b.c`, raw `<a target="_blank" href="https://example.org">`, `file:///etc/hosts`, `javascript:alert(1)`; raw `<meta http-equiv="refresh" content="1;url=https://evil.example">`), `b.md`, `notes.txt`, `sub dir/c.md`. Temporary env-guarded harness (not committed) replaces `performLink` with a recorder (passes `.openDocument` through), clicks each link with posted `NSEvent` mouse-down/up at its center (scrolled into view first; no Accessibility needed):
  - heading ids `intro`, `intro-1`, `c--go`, `custom` (and no second `custom`)
  - `#c--go` → `scrollY` changes, no reload (page `Marked.token` unchanged), recorder empty
  - `https`, `mailto`, `_blank` → `.openExternal` with the exact URL
  - `b.md`, `b.md#x` → second window for `b.md` (one window, D31), opened at the top; `sub dir/c.md` → its window
  - `notes.txt` → `.reveal(…/notes.txt)`; `missing.md` → `.openDocument`, then an error alert (sheet or window) is present; close it
  - `file:`, `javascript:` → nothing recorded
  - meta refresh: after 3 s nothing recorded, page token unchanged
  - shell reload (terminate path) still loads; `make test` green
  - ≥ 2 s between launches; launch with `--args -ApplePersistenceIgnoreState YES`
- [ ] I6.3 Manual (person at the keyboard): click a web link → default browser opens; click `notes.txt` → Finder reveals it
- [ ] I6.4 code-reviewer loop (+ `mc-code-security`: hostile links) until clean (max 5) → `design/s6-review.md`; tick S6 in `design.md`; commit on `s6-links`

## Merge conflicts

- C2 `userScripts`: one line in W6; C3 `WebView` coordinator: `decidePolicyFor` in W6, effects in K3 (both already counted in `estimates.md`)

## Deferred

- A link to the current document with a fragment (`a.md#sec` from `a.md`) focuses the same window and does not scroll (D17 literal: `.md` → new window at top)
- `file://` links (cancelled, like `file://` images, D25)

## Resolved questions (user, 2026-10-09, D34)

1. Self-link `this.md#sec`: D17 literal (focus, no scroll), deferred
2. `file://` links: cancel (as D25)
3. Missing link target: system error alert (`presentError`)

No open questions.
