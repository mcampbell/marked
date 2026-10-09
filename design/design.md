# Marked clone — design

Native macOS markdown reader. Read-only. Live reload with scroll-to-change. Q&A behind each decision: `grill.md`.

## Decisions

- SwiftPM only (no Xcode). `Makefile`: `build`, `test` (Swift Testing needs CLT `-F` flags), `app` (assembles `Marked.app`: binary → `Contents/MacOS`, top-level `Resources/` → `Contents/Resources`, ad-hoc `codesign -s -` over the whole bundle), `run` (`app` + `open`). No SwiftPM `resources:` and no `Bundle.module`; app loads via `Bundle.main`. Info.plist: `UTImportedTypeDeclarations` for `net.daringfireball.markdown` (conforms `public.plain-text`, extensions `md`, `markdown`, `mdown`), `CFBundleDocumentTypes` role Viewer for that UTI only; `MarkdownDocument.readableContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]`. No `public.plain-text` claim (would grab every `.txt`)
- Min macOS 14. SwiftUI `DocumentGroup(viewing:)` → read-only, multi-window, File>Open, Open Recent, Finder Open With, drag-drop, `open -a` for free
- `DocumentGroup` supplies only the URL: `ReaderView` reads `@Environment(\.documentConfiguration)?.fileURL`. `MarkdownDocument.init` stores raw bytes, never throws on decode. `FileWatcher` (S0) owns every read: S0 ships `read()` (bytes → UTF-8 decode) used for the first render; non-UTF-8 at first open → S0 renders a plain error message in the page. S1 adds the 0.5s poll, diff, and the reload banner (Q10). Viewer-only document has no save path, so no NSDocument write conflict; any NSDocument reload of its bytes is ignored. File unreadable at open time → system open alert (accepted; no window exists yet)
- Render: `swiftlang/swift-cmark` pinned `.revision("0c8947bbd58c491c54aae114aca40621cddc8357")` (gfm head 2026-10-09; products `cmark-gfm` + `cmark-gfm-extensions` confirmed in its Package.swift). Extensions: table, strikethrough, autolink, tasklist. Options: `CMARK_OPT_SOURCEPOS | CMARK_OPT_UNSAFE`
- Soft line breaks (a newline with no blank line) render exactly like one line: `CMARK_OPT_NOBREAKS` writes them as spaces, so the HTML is identical and find (S3) matches across them. A blank line still starts a new paragraph. Hard breaks (two trailing spaces or `\` at line end) stay `<br>` per CommonMark. Pinned by `HTMLRendererTests` (`softBreaksRenderLikeOneLine`). No CSS may set `white-space: pre*` on body text
- `==` stays literal inside code blocks and inline code (Marked 2 wrongly renders it as a highlight there). cmark-gfm has no highlight syntax, so `==` is literal everywhere today. Pinned by `HTMLRendererTests` (`doubleEqualsLiteralIn*`). Any future highlight feature must skip code
- WKWebView. `allowsContentJavaScript = false`. All app JS in `.defaultClient` world: `WKUserScript(source:injectionTime:forMainFrameOnly:in: .defaultClient)` and every call the async overload `try await callAsyncJavaScript(_:arguments:in: nil, contentWorld: .defaultClient)` (SDK-checked 2026-10-09: async form uses `contentWorld:`; `in: nil, in:` is the completion-handler form). Never page world. Spike (a) proves both run with page JS off; it gates the hook design, so it runs first in S0
- Load: `WKURLSchemeHandler` for scheme `marked:`, read-only, GET only, two hosts. No `<base>`, no `baseURL`/`loadFileURL` reliance:
  - `marked://app/base.css` → the only file fetched by URL; shell links it by absolute URL. Handler serves nothing else on this host (403)
  - JS (`marked.js`, `js/*`, `vendor/mermaid.min.js`) is never fetched: Swift reads it from `Bundle.main` and passes it as `WKUserScript` source. Style CSS (`styles/*`) likewise read by Swift and sent as text via `Marked.setStyle`. Shell HTML read by Swift and served for the reserved name below
  - `marked://doc/<abs-dir>/__marked__.html` → the shell. Page URL sits in the document dir, so relative URLs (`img.png`, `../img/x.png`) resolve naturally. Reserved name `__marked__.html`; a real file of that name is never served
  - `marked://doc/<abs-path>` → local image file, added by S7 (rules: see Security). Before S7: 403, so images are broken but the page renders
  - Path ↔ URL in `MarkedCore/DocURL.swift`: percent-encode each path component (`.urlPathAllowed` minus `#?;`), decode on serve. Round-trip tests: spaces, `#`, `?`, `%`, non-ASCII. Encoding is S0 (shell URL needs it). S7 serve rule: decoded path → `resolvingSymlinksInPath()` → must be an existing regular file with an image extension (Security), else 403. `Content-Type` = `UTType(filenameExtension:)?.preferredMIMEType` (no hand map; checked on macOS 26: `svg` → `image/svg+xml`, `ico` → `image/vnd.microsoft.icon`, `css` → `text/css`); shell → `text/html; charset=utf-8`. `DocURL` test asserts `svg`, `png`, `css`
- Page = shell HTML loaded once. Each content change → `Marked.render(html, changedLine)` via `callAsyncJavaScript`. No full reloads → no flicker, keep state
- `Marked.render(html, changedLine)` pipeline: swap `#content` → `await` each registered hook with `{changedLine}`. Render itself does no scroll. Scroll + flash = S1 hook in `js/scroll.js`. Features register hooks; they never edit `marked.js`
- Hook phases fixed in S0, run in order, hooks within a phase run in parallel: `transform` (S5 mermaid, S8 highlight, S11 syntax; they touch disjoint DOM: mermaid only `pre code.language-mermaid`, highlight never inside code, syntax only `pre > code.language-*` minus mermaid) → `decorate` (S3 find re-apply) → `position` (S1 scroll). `Marked.hook(phase, fn)`. Registration order is irrelevant
- Watcher: poll mtime+size every 0.5s on the `fileURL` from `documentConfiguration` (a `file://` URL, not `marked:`)
- Styles: `mono`/`serif`/`sans` CSS (font, max width, line height). Cmd-1/2/3. Global, `@AppStorage`. Default `sans`. Style files set only `:root` variables (`--font`, `--measure`, `--leading`); `base.css` consumes them. Frontmatter rule in `base.css` sets its own monospace font and does not read the variables → no precedence fight. Swap = `Marked.setStyle(cssText)` replaces `<style id="style">` text; no reload
- File errors (read/decode, S1): keep last good render, red banner, keep polling, auto-recover. Render errors: see Render lifecycle

### Render lifecycle (S0, frozen with `marked.js`)

- S0 owns the coordinator's single `WKNavigationDelegate`: `didFinish` (ready gate) and a minimal `decidePolicyFor`: allow this window's shell URL and same-page fragments, cancel everything else (links dead until S6, but the shell is never navigated away). S6 adds its rules inside this same method; it never installs a second delegate
- Shell-ready gate: `WKUserScript`s inject at `.atDocumentEnd` (DOM exists). `ready = true` on `webView(_:didFinish:)` for the shell navigation. Before ready, render and style calls only update the pending slot (latest source) and a pending style; on ready, send style then render. No other readiness handling in later slices

- One render in flight per window. Swift `await`s `callAsyncJavaScript("return await Marked.render(html, changedLine)")`, which resolves only after all three phases finish
- New source while a render is in flight → stored in a single pending slot (latest wins; intermediate saves dropped). On completion, dispatch the pending slot
- `changedLine` computed by S0 dispatch, at dispatch time, via seam `var changedLine: (_ lastRendered: String, _ next: String) -> Int? = { _, _ in nil }`. S0 ships the `nil` default (no scroll); S1 sets it to `LineDiff.firstChangedLine`. Dispatch is the single owner, so the baseline is always `lastRenderedSource` and coalesced saves scroll to the first change since what the user last saw. First render passes `nil`
- Hook failures are visible, not silent. Each hook call is wrapped in try/catch; on any failure `Marked.render` still finishes the remaining phases, prepends a visible `<div class="render-error">` (hook name + message) to `#content`, and resolves `{ok: false, errors: [...]}` (else `{ok: true}`). It never rejects, so the queue never stalls. Swift advances `lastRenderedSource` either way (the DOM now shows that source) and logs the errors. Degraded-with-note chosen over keeping the previous render: rollback would need a DOM snapshot per render. Expected Mermaid failures stay inside S5's own fallback and are not hook failures

### Security

Threat: hostile `.md` with raw HTML (allowed per Q8) shows or submits local files.

- S7: `marked://doc/` serves only image extensions (`png jpg jpeg gif webp avif bmp ico svg`); reserved `__marked__.html` → shell; anything else → 403. `svg` via `<img>` cannot run script
- S0: shell CSP meta: `default-src 'none'; img-src marked: data: https:; style-src marked: 'unsafe-inline'; font-src marked:; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'`. `unsafe-inline` styles needed for mermaid SVG. Spike (a) also confirms page CSP does not block `.defaultClient` scripts
- Accepted: remote https images load (tracking pixels possible), same as Marked 2
- S11: highlighted code is set only from highlight.js's escaped output; `marked://app/` gains exactly one file (`hljs.css`)
- S13: the `toc` message handler lives in `.defaultClient` only; Swift accepts an integer in range, nothing else
- Plain `http:` images do not load: App Transport Security blocks them and the design adds no `NSAllowsArbitraryLoadsInWebContent` exception. CSP matches (no `http:`)

## Layout (Swift conventions)

```
Package.swift
Makefile
Sources/MarkedCore/      # pure, tested
  HTMLRenderer.swift     # source → HTML (cmark)
  Frontmatter.swift      # S4
  LineDiff.swift         # S1
  DocURL.swift           # S0 path ↔ marked: URL; S7 serve rule + MIME
  Style.swift            # S2
Sources/Marked/          # app
  MarkedApp.swift        # DocumentGroup + .commands
  MarkdownDocument.swift # FileDocument, read-only, raw bytes only
  ReaderView.swift       # SwiftUI wrapper, banner, find bar slot
  WebView.swift          # NSViewRepresentable + coordinator; userScripts list
  SchemeHandler.swift    # `marked:` scheme: S0 shell + base.css; S7 local images
  FileWatcher.swift      # S0 `read()`; S1 adds poll
  FindBar.swift          # S3
Resources/               # copied by `make app`, not a SwiftPM resource
  shell.html, base.css, marked.js
  styles/{mono,serif,sans}.css   # S2
  js/{scroll,find,mermaid-hook,anchors,highlight}.js
  js/toc.js                      # S10, S13
  js/syntax.js                   # S11
  vendor/mermaid.min.js          # S5, pinned
  vendor/highlight.min.js, vendor/hljs-github.css  # S11, pinned
Sources/MarkedCore/TOC.swift     # S10 heading list from bridge; S13 index check
Tests/MarkedCoreTests/
Scripts/Info.plist
```

## Slices

Sliced design: 13 slices. S0 first. S1–S8 run as parallel streams after S0, one subagent each. (S7 split out of S0 on 2026-10-09 to keep S0 at the scale ceiling.) S10–S13 added 2026-10-09 after S0–S8 landed (grill: D36–D45).

| # | Slice | Delivers (usable alone on top of S0) | Touches |
|---|---|---|---|
| S0 ✅ | Walking skeleton | Open `.md` → rendered page (GFM, sans). Owns first-open lifecycle: `FileWatcher.read()`, shell-ready gate, render dispatch (see Render lifecycle). `.app` bundle. `make test` green. JS bridge + hook registry. `marked:` scheme handler: shell + `base.css` only. Shell CSP. `DocURL` encoding. Spikes: (a) `WKUserScript` + `callAsyncJavaScript` run in `.defaultClient` with page JS off, (c) signed `.app` launches from Finder and loads `shell.html` from `Contents/Resources`, (d) doc in a spaced path renders; `#frag` link reaches `decidePolicyFor` (`linkActivated`) and `.allow` yields a same-document scroll: no reload, `Marked` global and find state survive | all base files |
| S7 ✅ | Local images | Relative images (`img.png`, `../x.png`) load. Serve rule (symlinks resolved, regular file, image ext only), `Content-Type` via `UTType`. Cache-busting: `ImageStamp` appends `?v=<mtime>` to local `<img src>` at render time, so an edited image shows on the next render. Check: fixture dir with a spaced path, both images load; non-image path → 403 | `SchemeHandler` (doc-file route), `DocURL` (serve rule + MIME, tests) |
| S1 ✅ | Live reload + scroll | Save in editor → view updates ≤1s, scrolls to first changed block, flashes it. Missing/unreadable/non-UTF-8 → banner | `FileWatcher` (adds poll to S0's `read()`), `LineDiff`, `js/scroll.js`, `ReaderView` (sets S0 dispatch's `changedLine` seam to `LineDiff.firstChangedLine`) |
| S2 ✅ | Styles | Cmd-1/2/3 swap mono/serif/sans, all windows, persisted | `Style`, `styles/*.css`, `MarkedApp.commands`, `WebView` |
| S3 ✅ | Find | Cmd-F / Ctrl-F bar, highlight all, "n of m", Enter/Cmd-G next, Shift-Cmd-G prev, Esc close. Re-apply after render (hook) | `FindBar`, `js/find.js`, `MarkedApp.commands`, `ReaderView`, `WebView` (find bridge: query/next/prev → match index + count) |
| S4 ✅ | Frontmatter | Line-1 `---` block → verbatim monospace block, any style | `Frontmatter`, `HTMLRenderer`, `base.css` |
| S5 ✅ | Mermaid | ` ```mermaid ` → diagram. Bad diagram → error + source. Offline. Checks: flowchart arrowheads (`url(#marker)`) render; fixture with one good, one syntax-bad, one render-bad diagram → good renders, both bad show source + error, later phases still run | `vendor/mermaid.min.js`, `js/mermaid-hook.js`, `WebView` |
| S6 ✅ | Links | Web link → browser. `.md` link → new window. `#anchor` → in-page | `WebView` coordinator (nav delegate), `js/anchors.js` |
| S8 ✅ | Highlight | `==text==` outside code → `<mark>text</mark>`. Literal inside `pre`, `code`, `kbd`, `samp` (Marked 2 bug, D23). Shared helper + node test step are in the S0 baseline, so no prerequisite beyond S0 | `js/highlight.js`, `Tests/js/highlight.test.mjs`, `WebView.userScripts` (one line) |
| S10 ✅ | TOC sidebar | View > Show Sidebar (Ctrl-Cmd-S) toggles a leading sidebar: every `h1`–`h6`, indented by level. Hidden by default; open state global, persisted. Refreshes after every render. Click → heading scrolls to top. No headings → "No headings" | `MarkedCore/TOC.swift` + tests, `js/toc.js` + `Tests/js/toc.test.mjs`, `ReaderView` (`NavigationSplitView`), `WebView` coordinator (TOC bridge, refresh on render), `MarkedApp.commands` (`SidebarCommands`), `userScripts` (one line) |
| S11 ✅ | Syntax highlight | ` ```lang ` fence with a language highlight.js knows → colored, GitHub light theme, all styles. Unlabeled, unknown, `mermaid` → plain. Offline | `vendor/highlight.min.js` + `vendor/hljs-github.css` (+ `VERSION`, LICENSE), `js/syntax.js` + `Tests/js/syntax.test.mjs`, `SchemeHandler` + `DocURL.appFile` (tested) + `shell.html` (serve/link `marked://app/hljs.css`), `base.css` (`.hljs` overrides), `userScripts` (two lines) |
| S12 ✅ | Print | File > Print… (Cmd-P) → system print panel for the key window; its "Save as PDF" is the PDF export. Current style font, full paper width, backgrounds printed, no header/footer, no break inside code/diagram/table row, heading kept with next block, find highlights hidden | `WebView` coordinator (`print()`, `shouldPrintBackgrounds`), `MarkedApp.commands` (`CommandGroup(replacing: .printItem)`), `base.css` (`@media print`) |
| S13 ✅ | TOC scroll-spy | While scrolling, the sidebar marks the heading being read. Needs S10 | `js/toc.js` (scroll listener), `WebView` coordinator (message handler `toc` in `.defaultClient`), TOC sidebar view (current mark), `MarkedCore/TOC.swift` (index check + tests) |

Merge order (by value): S0 → S1 → S7 → S4 → S2 → S3 → S5 → S6 → S8. Every slice can start right after S0: the shared `requiredResource(subdirectory:)` and the Makefile node test step live in the S0 baseline. After S0, any order works because S0 fixes the load path (scheme handler), hook phases, render lifecycle (ready gate, serialization), and JS world; no slice edits another slice's behavior. Only R1 (scroll after mermaid) needs a joint check once S1 and S5 have both landed, whichever is second.

S10–S13: S10, S11, S12 start in parallel on top of `s8-highlight` (or `main` once the stack lands). S13 starts after S10 (extends `js/toc.js` and the sidebar). Merge order (cheapest first): S11 → S12 → S10 → S13. R3 (printed syntax colors) is a joint check once S11 and S12 have both landed.

### Module seams (why parallel works)

- Swift logic per feature = own file in `MarkedCore` with own tests
- JS per feature = own file, registered as hook in a named phase; `marked.js` render pipeline frozen after S0
- `WebView.userScripts` = array; each slice appends one line
- Frontmatter trick: replace frontmatter lines with blank lines before cmark → cmark sourcepos stays absolute → S1 scroll needs no frontmatter knowledge. Prepend `<pre class="frontmatter" data-sourcepos="1:1-N:1">`
- Mermaid: cmark emits `<pre data-sourcepos><code class="language-mermaid">`; JS hook replaces it with `<div class="mermaid" data-sourcepos=…>` (copies the attribute) holding the SVG. Per node, sequentially: `try { const {svg} = await mermaid.render(uniqueId, src); wrapper.innerHTML = svg } catch (e) { keep <pre> source + error note }`. Covers parse and layout/SVG failures alike; hook never rejects; one diagram at a time (no shared temp-id clash). No `mermaid.run`. S5 confirms behavior on the pinned version No Swift renderer change → no S4 conflict
- Find skips text inside mermaid `<svg>`
- Find (S3) must match across inline element boundaries (`<em>`, `<strong>`, S8 `<mark>`), since highlight splits text nodes

### S8 highlight rules (tested in `Tests/js/highlight.test.mjs`)

- JS `transform` hook, post-render DOM walk over text nodes of `#content`; skip any node inside `pre`, `code`, `kbd`, `samp`, `div.mermaid`
- Pure `splitHighlights(text) -> [{text, mark}]`: `==` + non-space … non-space + `==`, shortest match, same text node only; `====` and `== x ==` stay literal
- Build `<mark>` with `textContent` (no HTML injection)
- Deferred edge cases: a highlight spanning inline markup (`==a *b* c==`); backslash-escaped `\==` (cmark drops the backslash before JS sees the text)
- Swift `HTMLRendererTests` keep pinning literal `==` in code at the renderer level; the JS test pins it at the DOM level

### S6 navigation rules (`decidePolicyFor navigationAction`)

S6 extends S0's existing delegate method (see Render lifecycle); `didFinish` and the ready gate stay untouched. Rules apply in order; first match wins.

- URL equals this window's shell URL (`marked://doc/<doc-dir>/__marked__.html`, no fragment) → allow. Covers the app-initiated first load (`navigationType == .other`); without it the "Other" rule below reveals the shell in Finder and the window never loads. S6 check: open a fresh window with the delegate installed → page renders
- Same page URL + fragment → allow. Page URL has no `<base>`, so `#x` is a same-document scroll by default
- cmark-gfm emits no heading ids → `js/anchors.js` (`decorate` phase) adds GitHub slugger ids to `h1`–`h6`: lowercase, drop punctuation except `-` `_`, keep Unicode letters/digits, spaces → `-`; duplicates get `-1`, `-2`, …; headings that already have an `id` (raw HTML) keep it and reserve it. S6 smoke fixture: two "Intro" headings + "C++ & Go!" → `intro`, `intro-1`, `c--go`
- `http`, `https`, `mailto` with `navigationType == .linkActivated` → `NSWorkspace.shared.open`, cancel. Any other navigation type (e.g. `<meta http-equiv="refresh">` in a hostile file, type `.other`) → cancel, never open (S0 review M1)
- `marked://doc/<path>` whose URL **path** extension is `md`/`markdown`/`mdown` (query and fragment ignored; new window opens at top) → map to `file://<path>` → `NSDocumentController.shared.openDocument(withContentsOf:display: true)`, cancel. S6 check: this opens a `DocumentGroup` window
- Other `marked://doc/<path>` (pdf, txt, …) → `NSWorkspace.shared.activateFileViewerSelecting([fileURL])` (reveal in Finder), cancel. Reveal, not open: a hostile link to an `.app` or script must not launch on click
- Anything else → cancel

### S1 change rules (tested in `LineDiffTests` + manual)

- `LineDiff.firstChangedLine(old, new) -> Int?`: 1-based first line where line arrays differ; equal prefix but different length → `min(count)+1`; identical → `nil` (no scroll, no flash)
- Whitespace-only changes count as changes (no normalizing)
- Scroll target (JS): deepest element whose `data-sourcepos` range contains the line; none (pure deletion, blank line) → first block starting after it; none after → last block
- Edit inside frontmatter → frontmatter `<pre>` (has `data-sourcepos`)
- First render of a window → no scroll, no flash; only reloads scroll

### S10 TOC rules

- `js/toc.js` is an API, not a hook: `Marked.toc.headings()` → `[{level, text}]` for `#content h1`–`h6` in document order (raw-HTML headings included); `text` = `textContent`, whitespace collapsed, trimmed. `Marked.toc.go(i)` → same query, `scrollIntoView({block: "start"})`, instant, no flash; returns `false` when `i` is out of range (doc changed under the click)
- Swift `TOC.parse(raw) -> [TOCEntry]` (pure, tested): array of `{level: 1…6, text: String}`, else throw (log + empty list). Indent = level − smallest level in the doc. Empty text → shown as "—"
- Refresh: after every completed render (`RenderQueue.onRendered`, beside the find call) and after a shell reload. Style switch does not refresh (same headings)
- Click = a `Button` per row, never `List(selection:)`: S13 sets the current mark without causing a scroll (no feedback loop)
- Sidebar: `NavigationSplitView(columnVisibility:)` bound to `@AppStorage("tocVisible")` (default `false`), so all windows show/hide together, like styles. `SidebarCommands()` gives View > Show/Hide Sidebar, Ctrl-Cmd-S. Find bar and banner stay above the web view in the detail column
- S10 spike: `SidebarCommands` toggle writes back into the persisted binding in a `DocumentGroup` window. Fails → own `Toggle` in `.commands` on the same `@AppStorage` key (global, so no key-window lookup)

### S11 syntax rules (tested in `Tests/js/syntax.test.mjs`)

- `js/syntax.js` `transform` hook: each `#content pre > code` with a `language-<x>` class. Pure `langOf(className)` → first `language-` suffix, lowercased, or `null`. Skip `null`, `mermaid`, and `!hljs.getLanguage(x)` (aliases like `js`, `sh` resolve). Else `code.innerHTML = hljs.highlight(code.textContent, {language: x, ignoreIllegals: true}).value`, add class `hljs`
- Safety: only highlight.js's escaped `.value` is assigned; never source text as HTML. Node test: `<script>` in a fence stays text
- `<pre>` keeps `data-sourcepos` (S1 scroll unchanged). Find matches across token spans: `find.js` joins text per block and `PRE` is a block
- Theme: `vendor/hljs-github.css` served as `marked://app/hljs.css`, linked in `shell.html`. App-host allowlist becomes `base.css` + `hljs.css`; anything else 403. `base.css` sets `pre code.hljs { background: none; padding: 0 }` so the `pre` box stays the same in all styles
- Pin the highlight.js version at plan time (prebuilt common bundle, no build step); `vendor/VERSION` + LICENSE as for Mermaid. Plan checks the bundle defines one `hljs` global in the shared `.defaultClient` scope and loads in node for the test

### S12 print rules

- `CommandGroup(replacing: .printItem)`: "Print…" Cmd-P → key window's coordinator `print()`. Lookup reuses the `WKWebView` walk in `findController(in:)` (extract it to one helper). No document window → no-op
- `print()`: copy of `NSPrintInfo.shared`, `printInfo.dictionary()[NSPrintHeaderAndFooter] = false` (D44; no `headerAndFooter` property in the SDK), default margins → `web.printOperation(with:)` → `op.view?.frame = web.bounds` → `op.runModal(for: window, …)` (sheet). `cfg.preferences.shouldPrintBackgrounds = true`
- Prints the DOM at click time. A render that lands while the panel is open: not handled (accepted)
- `base.css` `@media print`: `#content { max-width: none; padding: 0 }`; `pre { white-space: pre-wrap; overflow-wrap: anywhere }` (scroll overflow does not print; `anywhere` breaks long unbroken tokens); `pre, div.mermaid, tr, img { break-inside: avoid }`; `h1`–`h6 { break-after: avoid }`; find highlights (`::highlight(find-*)`, `.find-*`) transparent
- S12 spikes: (p1) pages are not blank and paginate; (p2) panel "Save as PDF" → multi-page PDF, selectable text; (p3) mermaid SVG prints; (p4) the replaced item is the only Print item and it is enabled
- Check (manual, fixture: long code line, long table, mermaid, open find bar): print to PDF, read the PDF

### S13 scroll-spy rules

- `js/toc.js` adds a passive `scroll` listener, throttled to one `requestAnimationFrame`. Current = index of the last heading whose top is ≤ 8 px from the viewport top; none → `-1` (no mark). Bottom rule (D47): page scrollable and scrolled to its end → last heading whose top is inside the viewport. Posts `window.webkit.messageHandlers.toc.postMessage(i)` only when it changes. A `position` hook resets the last posted value and recomputes after each render
- Swift: `userContentController.add(WeakHandler(coordinator), contentWorld: .defaultClient, name: "toc")`; the wrapper breaks the controller → handler retain cycle. `TOC.current(raw) throws -> Int?` (pure, tested): integer `≥ -1` (`-1` → `nil`, no mark), else throws → log. Range (`< entries.count`) is checked at display: the `position` hook posts before `onRendered` refreshes the entries (s13-plan)
- Sidebar marks the current row and keeps it visible (`ScrollViewReader.scrollTo`). Setting the mark never scrolls the page (S10 click rule)
- S13 spike: `messageHandlers` is reachable from a `.defaultClient` user script with page JS off

## Merge conflicts (named, accepted)

- C1 `MarkedApp.commands`: S2 + S3 both add menu items; S10 `SidebarCommands`, S12 Print item
- C2 `WebView.userScripts` list: S1, S3, S5, S6, S8 each append a line; S10 one, S11 two
- C3 `WebView` coordinator: S2 style injection, S3 find bridge, S6 extends S0's `decidePolicyFor`, S7 render closure (one line) (S1 no longer touches it: render dispatch is S0); S10 TOC bridge + refresh, S12 `print()` + prefs, S13 message handler (S13 follows S10, so only S12 runs in parallel with it)
- C4 `ReaderView`: S1 adds banner, S3 adds find bar; S10 wraps the body in `NavigationSplitView` (no parallel S10–S13 conflict)
- C5 `base.css`: S11 `.hljs` overrides, S12 `@media print`

## Rework (named, accepted)

- R1 ✅ (S5 I5.2, 2026-10-09) Scroll must run after mermaid changes height. Guaranteed by phases (`position` after `transform`); the second of S1/S5 to land runs one manual check: edit inside a diagram → scroll lands on that diagram
- R2 Design gate, not a fix. If S0 spike (a) fails, stop S0 and return to the user. No fallback is pre-approved: a CSP nonce cannot override `allowsContentJavaScript = false`, so any fallback means enabling page JS (plus strict `script-src`), which changes the Q8 isolation model. Unestimated until decided
- R3 ✅ (2026-10-09, after merging S11 + S12 + S10) Printed syntax colors. Once S11 and S12 have both landed, the second runs one check: print a highlighted fence to PDF → token colors and the `pre` background show

## Per-slice check

- Core: Swift Testing in `Tests/MarkedCoreTests` (render, frontmatter edge cases, line diff, style map)
- UI: manual smoke list in each slice's PR

## Deferred (not in any slice)

- Image-only edits (image changes, `.md` unchanged) are not detected; single-quoted raw-HTML `src` and `srcset` are not cache-busted (S7)
- Bare-CR (classic Mac) line endings: `LineDiff` splits on LF only, so live scroll lands on line 1 for CR-only files (S1 review m2)
- Dark mode, TOML `+++`, large-file perf (incl. S11 highlight cost on huge fences)
- S11: auto-detect for unlabeled fences; languages beyond the common bundle
- S12: a separate File > Export as PDF… item (the print panel's "Save as PDF" covers it)

## Rejected

- Live toggle (Q13: always live)
- YAML parsing of frontmatter (Q7: verbatim only)
- Mermaid from CDN (Q12)
- Printed header, footer, or page numbers (D44)

## Unresolved questions

Resolved 2026-10-09 (user): local use only, no App Store. Bundle id `com.example.Marked`, app "Marked", ad-hoc `codesign -s -`, no notarization. No root at any build/run phase (see `s0-plan.md`).

Gate S5 only:

- ~~Mermaid version to pin?~~ Resolved D33: 11.17.2
