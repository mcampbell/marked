# S0 implementation plan — walking skeleton (parallel)

Source: `design.md` (S0 row, Decisions, Render lifecycle, Security S0 parts). Size: 4 pts (`estimates.md`, at the scale ceiling).

Done = open `.md` from Finder/File>Open → GFM page in sans, in a signed `.app`; `make test` green; checks (a), (c), (d) pass.

## Shape

```
W0 scaffold + frozen stubs (sequential, small)
 ├─ P1 app shell + WebKit + checks (a)(c)   ┐
 ├─ P2 HTMLRenderer + tests                 │ parallel, disjoint files,
 ├─ P3 DocURL + FileWatcher.read + tests    │ one builder subagent each,
 ├─ P4 RenderQueue + tests                  │ own git worktree
 └─ P5 marked.js + base.css                 ┘
I  integrate + check (d) + smoke (sequential)
```

Critical path: W0 → join(P1–P5) → I. The slowest stream sets the join. Assumption (no duration data): P1 is the longest branch (WebKit + bundle + two checks); P2–P5 are each a single file + tests. If another stream runs late, start I.2–I.3 checks that need only P1 + that stream's placeholder.

## Own decisions

- W0 freezes every signature as a compiling stub that returns a safe placeholder (not `fatalError`), so P1 can run the app before P2–P4 land. Streams fill bodies only, never edit `Package.swift`, never touch another stream's file → zero merge conflicts inside S0
- W0 also writes the final `shell.html` (CSP, fully specified), so P1 can run check (a) against the real CSP without waiting for P5
- `marked.js` contract: `Marked.ping()` returns `"pong"`. W0 ships it as a stub; P5 keeps it. Also `Marked.token = crypto.randomUUID()` set once per script injection (= per page load), used only by checks. P1 checks (a) against the stub
- `RenderQueue` + `RenderResult` live in `MarkedCore`: pure logic, async `send` closure injected → unit-testable without WebKit
- P1 wires `ReaderView`/`WebView` to the stub APIs of P2–P4. Integration (I) = merge and run, not new wiring
- Check (a) fails → P1 stops, report R2 to the user. P2–P4 survive unchanged (pure Swift). P5 likely survives (same JS, different injection)
- Worktree per stream: disjoint files, but separate `.build` dirs avoid SwiftPM lock contention
- S0 has no style switching: `base.css` `:root` defaults = sans
- Non-UTF-8 or read error at first open → markdown error text (`**Cannot display:** <reason>`) via the normal render path. S1 replaces it with the banner
- `@preconcurrency import WebKit` if Swift 6 strict concurrency rejects delegate conformance; WebKit-touching types `@MainActor`
- Local use only, never App Store. Bundle id `com.example.Marked`, ad-hoc signing (`codesign --force -s -`, no `--deep`: no nested code), `LSHandlerRank Alternate` (Unresolved Q1)
- No root at any phase. No `sudo` in any target. Everything writes under the repo (`.build/`, `build/Marked.app`) or `~/Applications`. Verified on this machine 2026-10-09 as uid 502: ad-hoc `codesign` + `codesign --verify` OK; `~/Applications` exists and is user-owned; `lsregister` present at `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister` (runs per user). Locally built app gets only `com.apple.provenance`, no quarantine → no Gatekeeper prompt. CLT test frameworks are only read from `/Library/Developer/CommandLineTools`

## File ownership

| File | Owner |
|---|---|
| `Package.swift`, `Makefile`, `Scripts/Info.plist`, `Resources/shell.html` | W0 (frozen after) |
| `Sources/Marked/{MarkedApp,MarkdownDocument,ReaderView,WebView,SchemeHandler}.swift` | P1 |
| `Sources/MarkedCore/HTMLRenderer.swift`, `Tests/MarkedCoreTests/HTMLRendererTests.swift` | P2 |
| `Sources/MarkedCore/DocURL.swift`, `Sources/Marked/FileWatcher.swift`, `Tests/MarkedCoreTests/DocURLTests.swift` | P3 |
| `Sources/MarkedCore/{RenderQueue,RenderResult}.swift`, `Tests/MarkedCoreTests/RenderQueueTests.swift` | P4 |
| `Resources/{marked.js,base.css}` | P5 |

## Tasks

### W0 — scaffold + stubs (sequential, main loop)

- [x] W0.1 `Package.swift`: tools 6.0, `.macOS(.v14)`. Targets `MarkedCore` (lib; deps `cmark-gfm` + `cmark-gfm-extensions` from `swiftlang/swift-cmark` `.revision("0c8947bbd58c491c54aae114aca40621cddc8357")`), `Marked` (executable → `MarkedCore`), `MarkedCoreTests`. No `resources:`
- [x] W0.2 Confirm C module names (`cmark_gfm`, `cmark_gfm_extensions`) by importing them in the `HTMLRenderer` stub; `swift build`
- [x] W0.3 `Makefile`: `build`; `test` with `-Xswiftc -F $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW)` (`CLT_FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks`); `app` (assembles `build/Marked.app`: binary → `Contents/MacOS`, `Resources/` → `Contents/Resources`, `Scripts/Info.plist`, `codesign --force -s -`); `run` (`app` + `open build/Marked.app`); `install` (`app` → `ditto` to `~/Applications/Marked.app` → `lsregister -f ~/Applications/Marked.app` so Finder Open With lists it); `clean`. No target uses `sudo`; `make` fails rather than prompt
- [x] W0.4 `Scripts/Info.plist`: `CFBundleExecutable Marked`, `CFBundleIdentifier com.example.Marked`, `CFBundlePackageType APPL`, `LSMinimumSystemVersion 14.0`; `UTImportedTypeDeclarations` `net.daringfireball.markdown` (conforms `public.plain-text`; exts `md markdown mdown`); `CFBundleDocumentTypes` role `Viewer`, `LSItemContentTypes [net.daringfireball.markdown]`, `LSHandlerRank Alternate`
- [x] W0.5 `Resources/shell.html` final: CSP meta exactly as `design.md` Security; `<link rel="stylesheet" href="marked://app/base.css">`; `<style id="style"></style>`; `<div id="content"></div>`
- [x] W0.6 Stubs with final signatures and placeholder bodies, all compiling: `render` → `"<p>stub</p>"`; `shellURL` → `marked://doc/__marked__.html`; `appURL` → `marked://app/<name>`; `filePath` → `nil`; `read` → `.success("stub")`; `RenderQueue.submit`/`markReady`/`shellWillReload` → no-op. Signatures:
  - `HTMLRenderer.render(_ source: String) -> String`
  - `DocURL.shellURL(forDocument: URL) -> URL`, `DocURL.appURL(_ name: String) -> URL`, `DocURL.filePath(from: URL) -> String?`
  - `struct RenderResult: Sendable { let ok: Bool; let errors: [String] }`
  - Wire shape (frozen, JS ↔ Swift): `Marked.render` resolves exactly `{ok: boolean, errors: string[]}`, each error `"<hook name>: <message>"`; success = `{ok: true, errors: []}`. P1 decodes `[String: Any]` → `ok as? Bool`, `errors as? [String]`; any decode miss throws (bridge failure, see `RenderQueue`), never defaults to success. W0 writes this shape as a comment at the top of the `marked.js` stub
  - `@MainActor final class RenderQueue { init(render: @escaping (String) -> String, send: @escaping (String, Int?) async throws -> RenderResult); var changedLine: (String, String) -> Int?; var onFailure: (Error) -> Void; func submit(_ source: String); func markReady(); func shellWillReload() }`
  - `enum ReadError: Error { case unreadable(String), notUTF8 }`, `FileWatcher.read(_ url: URL) -> Result<String, ReadError>`
  - App types: `MarkedApp`, `MarkdownDocument`, `ReaderView`, `WebView`, `SchemeHandler` (empty bodies that compile)
  - `Resources/marked.js` stub: `window.Marked = { ping: () => "pong", token: crypto.randomUUID() }` + wire-shape comment; `Resources/base.css` empty
- [x] W0.7 `swift build` + `make test` (zero tests) green → commit → fork worktrees

### P1 — app shell + WebKit + gate (builder)

- [x] P1.1 `MarkedApp`: `DocumentGroup(viewing: MarkdownDocument.self) { ReaderView() }`. `MarkdownDocument`: raw `Data`, `readableContentTypes = [UTType(importedAs: "net.daringfireball.markdown")]`, never throws on decode
- [x] P1.2 `SchemeHandler`: GET only. `app` host `/base.css` → `text/css`; `doc` host, last path component `__marked__.html` → shell bytes, `text/html; charset=utf-8`; else 403. Read shell + `base.css` from `Bundle.main` once
- [x] P1.3 `WebView` coordinator: `allowsContentJavaScript = false`; `setURLSchemeHandler(_:forURLScheme: "marked")`; `userScripts` array → `WKUserScript(.atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)`, S0 entry = `marked.js`; single `WKNavigationDelegate`: `didFinish` → `queue.markReady()`; `webViewWebContentProcessDidTerminate` → `queue.shellWillReload()` + reload shell URL; `queue.onFailure` → log + window subtitle "Render failed: <error>" (cleared on next successful render); `decidePolicyFor` allows the exact shell URL and same page URL + fragment, cancels all else. `send` = `try await webView.callAsyncJavaScript("return await Marked.render(html, changedLine)", arguments: [...], in: nil, contentWorld: .defaultClient)` (async overload; label is `contentWorld:`. The `in: nil, in:` form is the completion-handler overload with default `nil` handler: compiles, runs fire-and-forget, returns nothing — never use it here)
- [x] P1.4 `ReaderView`: from `documentConfiguration?.fileURL` → load `DocURL.shellURL` → `FileWatcher.read` → `queue.submit(text or error text)`. Window title = file name
- [x] P1.5 **Check (a)** (temporary debug hook, removed after): after `didFinish`, `try await webView.callAsyncJavaScript("return Marked.ping()", in: nil, contentWorld: .defaultClient)` → `"pong"`, and set `#content.textContent` from the same world → visible. Real CSP in place. Fail → STOP, report R2
- [x] P1.6 **Check (c)**: as a normal user, `make install`; `codesign --verify ~/Applications/Marked.app`; `open -a ~/Applications/Marked.app <fixture>.md` → window loads shell and shows "pong" (P2–P4 still placeholders)

### P2 — HTMLRenderer (builder)

- [x] P2.1 `cmark_gfm_core_extensions_ensure_registered()`; parser with `CMARK_OPT_SOURCEPOS | CMARK_OPT_UNSAFE`; attach `table strikethrough autolink tasklist`; `cmark_render_html(doc, opts, cmark_parser_get_syntax_extensions(parser))`; free everything
- [x] P2.2 Tests: heading has `data-sourcepos="1:1-…"`; table → `<table`; `~~x~~` → `<del>`; `- [ ] a` → checkbox; raw `<details>` passes through; empty input → empty string

### P3 — DocURL + FileWatcher.read (builder)

- [x] P3.1 `DocURL`: per-component percent-encoding (`.urlPathAllowed` minus `#?;`); `shellURL` = `marked://doc/<enc-dir>/__marked__.html`; `appURL` = `marked://app/<name>`; `filePath(from:)` decodes `doc` host paths, `nil` otherwise
- [x] P3.2 Tests: round trip for spaces, `#`, `?`, `%`, `é`; shell URL ends `/__marked__.html`; `filePath` on `app` URL → `nil`
- [x] P3.3 `FileWatcher.read`: `Data(contentsOf:)` → `String(data:encoding: .utf8)`; errors → `.unreadable(localizedDescription)` / `.notUTF8`. No unit test (app target); covered in I.2

### P4 — RenderQueue (builder)

- [x] P4.1 Rules: before `markReady` → store pending only; one send in flight; new submits during flight overwrite the single pending slot; on completion dispatch pending; `changedLine(lastRenderedSource, next)` computed at dispatch; first dispatch passes `nil`; `lastRenderedSource` advances on `ok` and `!ok` (DOM shows the source, maybe degraded). `send` throws (bridge failure: decode miss, missing function, dead web process) → baseline NOT advanced, in-flight slot released, `onFailure(error)` called, no automatic retry; a newer pending source still dispatches. `shellWillReload()` → `generation += 1`, in-flight slot freed, `ready = false`, `lastRenderedSource = nil` (fresh DOM is empty), pending = latest submitted source; next `markReady` re-sends it with `changedLine = nil`. Every send captures `generation` at dispatch; on completion (success or throw) with a stale generation → discard entirely: no baseline change, no slot release, no `onFailure`, no dispatch. Stale WebKit completions can therefore never touch the new shell's state, and a never-completing old send cannot block the resend
- [x] P4.2 Tests (fake `send` with a continuation you resume by hand): submit before ready → no send; `markReady` → one send with latest; three submits mid-flight → exactly one follow-up send with the last; seam stub returning 7 → 7 sent, and receives `(lastRendered, next)`; first send gets `nil`; `ok: false` still advances baseline; `send` throws → `onFailure` called once, baseline unchanged (next seam call receives the old baseline), queue not stuck (next submit sends); `shellWillReload` + `markReady` → re-sends latest submitted with `nil`; stale completion: suspend send A, submit B, `shellWillReload`, `markReady` → B sent with `nil` while A still suspended; then resume A with success and (second run) with throw → baseline stays as set by B, B's slot not released, `onFailure` not called, no extra send

### P5 — marked.js + base.css (builder)

- [x] P5.1 `marked.js` (frozen after S0): keep `ping`; `Marked.hook(phase, fn)` for `transform | decorate | position` (unknown phase → throw); `Marked.render(html, changedLine)`: swap `#content.innerHTML`; per phase `await Promise.all(hooks.map(fn → try/catch, collect "<hook name>: <message>" strings))`; errors → prepend `<div class="render-error">`; return `{ok, errors}`; never rejects. `Marked.setStyle(css)` sets `#style` text
- [x] P5.2 `base.css`: `:root { --font: -apple-system, system-ui, sans-serif; --measure: 46em; --leading: 1.6 }`; body/`#content` consume the vars; `pre, code` monospace; `.render-error` red box; tables bordered
- [x] P5.3 Self-check: `node --check` if available, else `osascript -l JavaScript -e` parse; no DOM tests (covered in I)

### I — integrate + checks (sequential, main loop)

- [x] I.1 Merge P1–P5 (no shared files → no conflicts expected); remove P1 debug hook; `make test`; `make install`. Whole run as a normal user; any root prompt = defect
- [x] I.2 **Check (d)**: fixture `~/tmp/marked fixtures/a b/doc.md` (headings, `[jump](#target)`, raw `<a id="target">`) renders; read `Marked.token` → click → scrolls; `Marked.token` unchanged and coordinator `didFinish` count unchanged → no reload
- [~] I.3 Smoke (automated parts done: `open -a`, non-UTF-8 → error text, table/task/strike/autolink, external link blocked, iframe blocked by CSP, throwing hook → red box; NOT yet done, need a human at the GUI: Finder Open With, File > Open, drag onto Dock icon, two windows): Finder Open With; File > Open; drag onto Dock icon; `open -a`; two windows; non-UTF-8 → error text; table, task list, strikethrough, autolink; external link does nothing; `<iframe src="https://example.com">` blocked; temporary throwing hook → red `render-error` box, page still shown
- [x] I.4 `swift build` warning-free in `MarkedCore`; tick S0 in `design.md`

## Subagent prompts (each)

Give: this file path, the stream ID, its file-ownership row, `design.md` path. Rules: edit only owned files; keep W0 signatures; run `make test` (P2–P4) or `make app` (P1) before reporting. Include: "Time matters here: do not spend time that can be avoided, and the earlier a correct result is obtained, the better."

## Handoff to S1–S7

- S1: set `queue.changedLine`; add poll + banner; register `js/scroll.js` in `position`. Move read + submit out of `WebView.Coordinator.start` behind `FileWatcher` (e.g. `watch(url, onChange:)`), so the coordinator only owns the queue and shell load (S0 review coupling note)
- S2/S3/S5/S6: append to `userScripts`; S6 extends `decidePolicyFor` only
- S7: extend `SchemeHandler` doc-host branch + `DocURL` serve rule

## Unresolved questions

1. `LSHandlerRank Alternate` (Marked listed in Open With, never steals the `.md` default) OK?
2. swift-cmark C module names unverified until W0.2; if different, only imports change

Resolved 2026-10-09: local use only → ad-hoc signing, `com.example.Marked`, no `--deep`, no root anywhere.
