# S7 implementation plan — local images (parallel)

Source: `design.md` (S7 row, "Load" bullets, Security). Size: 2 pts (`estimates.md`; was 1 before cache-busting was added). Builds on `s1-live` @ `bf55ca1`.

Done = `![](img.png)`, `![](../x.png)`, `<img src="sub/a b.svg">` and absolute-path images in a document load; non-image paths and missing files get 403; an edited image shows its new content on the next render (cache-busting); `make test` green; live check in a spaced-path fixture passes.

## Shape

```
W7 frozen stubs (sequential, small)
 ├─ T1 DocURL serve rule + MIME + tests (MarkedCore)   ┐
 ├─ T2 SchemeHandler doc-file route + render wiring    │ parallel, disjoint files,
 └─ T3 ImageStamp cache-busting + tests (MarkedCore)   ┘ one builder each, own worktree
I7 integrate + live check (sequential)
```

Critical path: W7 → join(T1, T2, T3) → I7.

## Own decisions

- Split the serve rule into a pure function with an injected file probe, so tests cover it without file IO or `import Foundation` in the test file (CLT gap). The app supplies the real probe
- Probe = `resolvingSymlinksInPath()` + `FileManager.attributesOfItem` → `(resolvedPath, isRegularFile)`; any throw → `nil`
- Allowed extensions (lower-cased, checked on the **resolved** path, so a `x.png` symlink to `~/.ssh/id_rsa` is refused): `png jpg jpeg gif webp avif bmp ico svg`
- `Content-Type` = `UTType(filenameExtension:)?.preferredMIMEType` (verified on macOS 26 in the S0 plan review); fallback `application/octet-stream` never hit for the allowed list
- No read-root restriction (design decision: page JS is off, so no exfiltration); absolute-path images work too
- Read the whole file into memory: document images are small. No range requests
- `file://` image URLs stay blocked by CSP (`img-src marked: data: https:`); authors use relative or absolute paths
- Cache-busting (user, 2026-10-09): after rendering, `ImageStamp.apply` appends `?v=<mtime>` to each local `<img src>`. Mtime, not a per-render counter: `Marked.render` swaps `#content`, so every `<img>` is recreated each render; a counter would reload all images on every save (flicker), mtime changes the URL only when that image changed. Runs inside the queue's `render` closure, so mtimes are read at dispatch time
- `ImageStamp` scope: `<img ... src="...">` with double quotes (cmark's form for `![]()`, and most raw HTML). Resolves `src` against the shell URL (so relative and absolute paths both work); stamps only `marked://doc/` targets; skips `src` that already has `?` or `#`, `data:`, `https:`. Unescapes `&amp;` before resolving. Pure function, mtime lookup injected
- The serve rule ignores the query: `filePath(from:)` uses the URL path only
- Deferred: an image edit while the `.md` is unchanged is not detected (only the document is watched); single-quoted / unquoted raw-HTML `src` and `srcset` are not stamped (they still load, without busting)
- `file://` image URLs stay blocked by CSP (user, 2026-10-09)

## Frozen contracts (W7)

```swift
// MarkedCore/DocURL.swift (additions)
public struct FileInfo: Equatable, Sendable {
    public let resolvedPath: String
    public let isRegularFile: Bool
    public init(resolvedPath: String, isRegularFile: Bool)
}
public static let imageExtensions: Set<String>   // png jpg jpeg gif webp avif bmp ico svg
/// Resolved path to serve for a `marked://doc/...` request, or nil → 403.
public static func imageFile(for url: URL, probe: (String) -> FileInfo?) -> String?
public static func contentType(forPath path: String) -> String

// MarkedCore/ImageStamp.swift
public enum ImageStamp {
    /// Appends ?v=<mtime> to each local double-quoted <img src>; mtime(path) nil → leave src as is.
    public static func apply(_ html: String, shell: URL, mtime: (String) -> Double?) -> String
}
```

## File ownership

| File | Owner |
|---|---|
| Stubs in `DocURL.swift` | W7 (frozen after) |
| `Sources/MarkedCore/DocURL.swift` (bodies of the new API), `Tests/MarkedCoreTests/DocURLTests.swift` | T1 |
| `Sources/Marked/SchemeHandler.swift`, `Sources/Marked/WebView.swift` (render closure line only) | T2 |
| `Sources/MarkedCore/ImageStamp.swift`, `Tests/MarkedCoreTests/ImageStampTests.swift` | T3 |

## Tasks

### W7 — stubs (sequential, main loop)

- [x] W7.1 Branch `s7-images` from `s1-live`
- [x] W7.2 Add the frozen API above with placeholder bodies: `imageExtensions` real set; `imageFile` → `nil`; `contentType` → `"application/octet-stream"`; `ImageStamp.apply` → returns `html` unchanged
- [x] W7.3 `make test` green → commit → fork worktrees

### T1 — serve rule + MIME (builder)

- [x] T1.1 Tests first (no `import Foundation`; build URLs with `.init(string:)!`; fake `probe` closure):
  - `marked://doc/tmp/a.png`, probe → regular file → `"/tmp/a.png"`
  - percent-encoded path (`/tmp/a%20b/c.png`) → probe receives the decoded `"/tmp/a b/c.png"`
  - extension case: `A.PNG` → served
  - non-image extension (`.md`, `.txt`, none) → `nil`, probe not called
  - probe → `nil` (missing) → `nil`
  - probe → not a regular file (directory named `x.png`) → `nil`
  - symlink: request `.png`, probe resolves to `/Users/x/.ssh/id_rsa` → `nil` (extension checked on the resolved path)
  - reserved shell name `__marked__.html` → `nil` (handler serves the shell separately)
  - query is ignored: `marked://doc/tmp/a.png?v=12` → `"/tmp/a.png"`
  - `app` host or foreign scheme → `nil`
  - `contentType(forPath:)`: `.svg` → `image/svg+xml`, `.png` → `image/png`, `.JPG` → `image/jpeg`
- [x] T1.2 Implement: `filePath(from:)` → extension check → `probe` → regular-file check → extension re-check on `resolvedPath` → return `resolvedPath`. `contentType` via `UTType(filenameExtension: ext.lowercased())?.preferredMIMEType`

### T2 — SchemeHandler route (builder)

- [x] T2.1 After the shell branch: `else if url.host == DocURL.docHost, let path = DocURL.imageFile(for: url, probe: Self.probe)` → `body = try? Data(contentsOf: URL(fileURLWithPath: path))`, `type = DocURL.contentType(forPath: path)`. A failed read → 403 (existing path)
- [x] T2.2 `static func probe(_ path: String) -> FileInfo?`: `URL(fileURLWithPath: path).resolvingSymlinksInPath().path` → `FileManager.default.attributesOfItem` → `.type == .typeRegular`
- [x] T2.3 `WebView`: queue `render` closure = `{ ImageStamp.apply(HTMLRenderer.render($0), shell: shell, mtime: Self.mtime) }`; `static func mtime(_ path: String) -> Double?` via `FileManager.attributesOfItem` `.modificationDate`
- [x] T2.4 `make app` builds with no warnings in the file; `make test` stays green

### T3 — ImageStamp (builder)

- [x] T3.1 Tests first (no `import Foundation`; shell `marked://doc/tmp/d/__marked__.html` via `.init(string:)!`; fake `mtime` dictionary keyed by path):
  - `<img src="a.png" alt="x" />` → `src="a.png?v=12000"` when `/tmp/d/a.png` → 12.0 s (v = integer milliseconds); 12.0004 s → `v=12000`, 12.5 s → `v=12500`
  - `../up.png` → stamped via `/tmp/up.png`; absolute `/abs/p.png` → stamped
  - percent-encoded `a%20b.png` → mtime looked up as `/tmp/d/a b.png`; `src` keeps its encoding
  - mtime `nil` (missing file) → unchanged
  - `https://…`, `data:…`, `x.png?q=1`, `x.png#f` → unchanged
  - `&amp;` in `src` → resolved as `&`, output keeps `&amp;`
  - two images, one changed mtime → each gets its own `v`
  - single-quoted `src='a.png'` → unchanged (deferred scope)
  - non-`img` tags with `src` (e.g. `<source src>`) → unchanged
  - `<img data-src="other.png" src="a.png">` → only `src` stamped, `data-src` untouched (regression)
  - `<IMG SRC="a.png">` → stamped (case-insensitive)
  - `<img alt=' src="other.png"' src="a.png">` → only the real `src` stamped; `alt` text byte-identical (regression)
  - `<img alt="a > b" src="a.png">` → stamped (a `>` inside a quoted value does not end the tag)
  - `<img` + real newline + `src="a.png">` → stamped
  - `<!-- <img src="c.png"> -->` → comment unchanged
  - `<a title="<img src='x'>">` → unchanged (not a real `img` tag)
  - output differs from input only inside the stamped `src` values
- [x] T3.2 Implement with a quote-aware tag scan, not a single `src` regex (a lone regex cannot tell a real attribute from text inside another attribute's quotes). Two `NSRegularExpression`s, prototyped 2026-10-09:
  - attribute: `\s+([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?`
  - tag: `<!--[\s\S]*?-->|<([A-Za-z][^\s/>]*)((?:<attribute>)*)\s*/?>` — scanned left to right over the whole HTML, so comments and quoted values (including `>` and `<img` inside them) are consumed whole
  - for each tag named `img` (case-insensitive): walk its attributes, take the **first** `src` (case-insensitive); stamp only when it is double-quoted (group 2). Replace from the end so ranges stay valid
  - prototype results: `<img alt=' src="other.png"' src="a.png">` → `a.png`; `<img alt="a > b" src="a.png">` → `a.png`; `data-src` → ignored; newline before `src` → found; `<img>` inside a comment or inside another tag's attribute → ignored; `<IMG SRC>` → found; single-quoted `src` → ignored (deferred)

### I7 — integrate + live check (sequential, main loop)

- [x] I7.1 Merge T1, T2 **and T3** (copy files from worktrees; T3 replaces the identity `ImageStamp.apply` stub and adds `ImageStampTests`); `make test` (confirm `ImageStampTests` ran); `make install`
- [x] I7.2 (2026-10-09: rel 10px, up 12px, svg 16px, abs 14px load; txt, symlink, missing = 0; swap → rel 30px with new `v`, others keep their `v`) Fixture `~/tmp/marked fixtures/img dir/doc.md` (spaced path) with `img.png` beside it, `../up.png`, `sub/a b.svg`, an absolute-path image, `notes.txt` linked as an image, a symlink `evil.png` → a text file, and a missing image. Temporary env-guarded harness (not committed) reads each `<img>`'s `naturalWidth` after load: the four real images > 0; the `.txt`, symlink, and missing ones = 0. Cache-busting: replace `img.png` with a different-size image, append a line to `doc.md` → after the render, `img.png`'s `naturalWidth` matches the new image and its `src` carries a new `v`
- [ ] I7.3 code-reviewer loop until clean (max 5); commit on `s7-images`; tick S7 in `design.md`

## Merge conflicts

- `SchemeHandler.swift`, `DocURL.swift` serve part, `ImageStamp.swift`: S7 only
- C3 `WebView.swift`: S7 changes the queue `render` closure (one line); S2/S3/S6 edit other parts of the coordinator

## Resolved questions (user, 2026-10-09)

1. Cache-busting: add it in S7 (`?v=<mtime>` via `ImageStamp`)
2. `file://` image URLs: leave blocked

No open questions.
