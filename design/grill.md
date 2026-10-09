# Marked2-clone design grill — 2026-10-09

## Facts found
- Repo /Users/michael.campbell/dev/marked: empty, no commits, no estimates.md/ADRs
- Toolchain: Swift 6.2.3, Command Line Tools only (no Xcode) → SwiftPM build, no .xcodeproj
- OS: macOS 26.7.1, arm64

## Q&A
- Q1 Renderer → WKWebView + swiftlang/swift-cmark (GFM, sourcepos). Fonts via CSS.
- Q2 Open model → real .app bundle via build script, multi-window (one per file), File>Open, Finder Open With, drag-drop, `open -a`.
- Q3 Live scroll → always scroll to first changed block, centered, brief highlight flash.
- (user, mid-session) All docs incl. grill → ./design. Other dirs/files: normal Swift conventions (Package.swift, Sources/, Tests/).
- Q4 Watcher → poll mtime+size every 0.5s; re-read on diff. Survives atomic saves.
- Q5 Style → font + max width + line height per style (CSS file). Global across windows. Persist in UserDefaults.
- Q6 Find → bar (Cmd-F / Ctrl-F), JS-based: highlight all hits + 'n of m' count, Enter/Cmd-G next, Shift-Cmd-G prev, Esc close. Re-apply after live reload if bar open.
- Q7 Frontmatter → line 1 exactly `---`, closed by `---` or `...`. Unclosed → normal markdown. Verbatim monospace block, style-independent. No YAML parse.
- Q8 Raw HTML → allowed (cmark UNSAFE); page JavaScript disabled (WKWebpagePreferences.allowsContentJavaScript=false). App JS via evaluateJavaScript unaffected.
  - Post-review note: design uses `callAsyncJavaScript` + `WKUserScript` in `.defaultClient` world; unverified until S0 spike (a).
- Q9 Links/images → relative images resolve from file dir. Web link → default browser. .md link → new app window. #anchor → scroll in place. (Refined by D17.)
- Q10 File errors → keep last good render + red banner, keep polling, auto-recover. Non-UTF-8 → banner, no render.
- Probe: plain `swift test` fails under CLT (no Testing/XCTest module). Swift Testing passes with `-Xswiftc -F <CLT>/Library/Developer/Frameworks` + matching `-Xlinker -F/-rpath`. Wrap in script/Makefile.
- Q11 Tests → pure logic in `MarkedCore` lib target, Swift Testing via `make test`. App/WebView → manual smoke checklist per slice.
- (user, mid-session) New feature: render Mermaid diagrams inline (```mermaid fenced blocks). Runs as app-injected JS (allowed with page JS off, per Q8).
- Q12 Mermaid → vendored mermaid.min.js, pinned version, offline. securityLevel 'strict'. Bad diagram → error + source shown in place.
- Q13 Live toggle → none. Always live. (YAGNI)

## Author decisions from reviews (not user Q&A; override any)

- D14 Min macOS 14 (`documentConfiguration.fileURL` for the watcher)
- D15 Remote images https only. ATS blocks plain http; no `NSAllowsArbitraryLoadsInWebContent` exception
- D16 Local file serving: `marked://doc/` serves image files only (+ reserved shell name); CSP blocks frames, objects, forms, `<base>`. `marked://app/` serves `base.css` only; JS/styles injected as text
- D17 Links (refines Q9): `.md` link matched on URL path, fragment ignored, new window at top. Other local files → reveal in Finder, never open (hostile `.app` link must not launch)
- D18 Heading ids: GitHub slugger rules via `js/anchors.js`, dupes `-1`, `-2`
- D19 Mermaid errors: sequential per-diagram `mermaid.render` in try/catch; failure (parse or render) → source + error note; others still render. (Replaces parse-then-run; earlier review claim that `run` stops at first error was wrong — 11.12.0 collects errors and throws after the loop)
- D20 (user-approved) Split S0: S0 keeps skeleton, lifecycle, ready gate, bridge, shell-only handler, `DocURL` encoding, CSP, spikes a/c/d. New S7 "Local images" (serve rule, MIME) runs parallel with S1–S6
- D21 (user) Local use only, never App Store. Ad-hoc signing, `com.example.Marked`. No root at any phase of build/run; install to `~/Applications` + per-user `lsregister`
- D22 (user) S1: banner after 2 missing polls; smooth scroll; flash `#fff3a0` 1.2s; node optional for JS tests
- D23 (user) `==` must render literally inside code blocks and inline code (Marked 2 bug: shows it as highlight). Pinned by HTMLRendererTests
- D24 (user wants `==text==` highlight outside code eventually; author decision) New slice S8: JS `transform` hook, never inside code; no Swift renderer change (avoids S4 conflict); depends only on S0
- D25 (user) S7: add image cache-busting (`?v=<mtime>` via `ImageStamp`, mtime not per-render to avoid flicker); `file://` images stay blocked. Image-only edits without a `.md` change deferred
- D26 (user) Text wrapped across lines with no blank line renders the same as one line. `CMARK_OPT_NOBREAKS` (soft break → space, identical HTML, find works across it). Pinned by HTMLRendererTests
- D27 (user) Frontmatter block shows both fences (`---` … `---`/`...`); `---` anywhere other than line 1 is normal markdown
- D28 (user) Two trailing spaces or a trailing backslash = CommonMark hard line break (`<br />`), unchanged. Pinned by HTMLRendererTests
- D29 (user) S2: style values accepted (mono ui-monospace/80ch/1.5, serif New York/38em/1.65, sans system/46em/1.6); small scroll jump on style switch accepted
- D30 (user) S3: case-insensitive only (no options); frontmatter searchable; find bar above the error banner
- D31 (user) S9: open adds a window per document in one app; app quits when all windows close (one-copy-per-document was allowed, not needed). Reopening an open document focuses it
- D32 (user) Cancelling the Open dialog at launch quits the app. Already covered by S9 (dialog is the last window); verified live, no extra code
- D33 (user) S5: pin mermaid 11.17.2 (not 12.x); default Mermaid theme, no S2 font tie-in; load-cost call (eager vs lazy injection) made by the author after the W5.4 measurement
- D34 (user) S6: self-link `this.md#sec` keeps D17 literal (focus, no scroll; deferred); `file://` links cancelled (as D25); missing link target → system error alert (`presentError`)
