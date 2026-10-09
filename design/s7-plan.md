# S7 implementation plan — local images (parallel)

Source: `design.md` (S7 row, "Load" bullets, Security). Size: 1 pt (`estimates.md`). Builds on `s1-live` @ `bf55ca1`.

Done = `![](img.png)`, `![](../x.png)`, `<img src="sub/a b.svg">` and absolute-path images in a document load; non-image paths and missing files get 403; `make test` green; live check in a spaced-path fixture passes.

## Shape

```
W7 frozen stubs (sequential, small)
 ├─ T1 DocURL serve rule + MIME + tests (MarkedCore)   ┐ parallel, disjoint files,
 └─ T2 SchemeHandler doc-file route (app)              ┘ one builder each, own worktree
I7 integrate + live check (sequential)
```

Critical path: W7 → join(T1, T2) → I7.

## Own decisions

- Split the serve rule into a pure function with an injected file probe, so tests cover it without file IO or `import Foundation` in the test file (CLT gap). The app supplies the real probe
- Probe = `resolvingSymlinksInPath()` + `FileManager.attributesOfItem` → `(resolvedPath, isRegularFile)`; any throw → `nil`
- Allowed extensions (lower-cased, checked on the **resolved** path, so a `x.png` symlink to `~/.ssh/id_rsa` is refused): `png jpg jpeg gif webp avif bmp ico svg`
- `Content-Type` = `UTType(filenameExtension:)?.preferredMIMEType` (verified on macOS 26 in the S0 plan review); fallback `application/octet-stream` never hit for the allowed list
- No read-root restriction (design decision: page JS is off, so no exfiltration); absolute-path images work too
- Read the whole file into memory: document images are small. No range requests
- `file://` image URLs stay blocked by CSP (`img-src marked: data: https:`); authors use relative or absolute paths
- Image edits do not refresh while a document stays open (see Unresolved Q1)

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
```

## File ownership

| File | Owner |
|---|---|
| Stubs in `DocURL.swift` | W7 (frozen after) |
| `Sources/MarkedCore/DocURL.swift` (bodies of the new API), `Tests/MarkedCoreTests/DocURLTests.swift` | T1 |
| `Sources/Marked/SchemeHandler.swift` | T2 |

## Tasks

### W7 — stubs (sequential, main loop)

- [ ] W7.1 Branch `s7-images` from `s1-live`
- [ ] W7.2 Add the frozen API above with placeholder bodies: `imageExtensions` real set; `imageFile` → `nil`; `contentType` → `"application/octet-stream"`
- [ ] W7.3 `make test` green → commit → fork worktrees

### T1 — serve rule + MIME (builder)

- [ ] T1.1 Tests first (no `import Foundation`; build URLs with `.init(string:)!`; fake `probe` closure):
  - `marked://doc/tmp/a.png`, probe → regular file → `"/tmp/a.png"`
  - percent-encoded path (`/tmp/a%20b/c.png`) → probe receives the decoded `"/tmp/a b/c.png"`
  - extension case: `A.PNG` → served
  - non-image extension (`.md`, `.txt`, none) → `nil`, probe not called
  - probe → `nil` (missing) → `nil`
  - probe → not a regular file (directory named `x.png`) → `nil`
  - symlink: request `.png`, probe resolves to `/Users/x/.ssh/id_rsa` → `nil` (extension checked on the resolved path)
  - reserved shell name `__marked__.html` → `nil` (handler serves the shell separately)
  - `app` host or foreign scheme → `nil`
  - `contentType(forPath:)`: `.svg` → `image/svg+xml`, `.png` → `image/png`, `.JPG` → `image/jpeg`
- [ ] T1.2 Implement: `filePath(from:)` → extension check → `probe` → regular-file check → extension re-check on `resolvedPath` → return `resolvedPath`. `contentType` via `UTType(filenameExtension: ext.lowercased())?.preferredMIMEType`

### T2 — SchemeHandler route (builder)

- [ ] T2.1 After the shell branch: `else if url.host == DocURL.docHost, let path = DocURL.imageFile(for: url, probe: Self.probe)` → `body = try? Data(contentsOf: URL(fileURLWithPath: path))`, `type = DocURL.contentType(forPath: path)`. A failed read → 403 (existing path)
- [ ] T2.2 `static func probe(_ path: String) -> FileInfo?`: `URL(fileURLWithPath: path).resolvingSymlinksInPath().path` → `FileManager.default.attributesOfItem` → `.type == .typeRegular`
- [ ] T2.3 `make app` builds with no warnings in the file; `make test` stays green

### I7 — integrate + live check (sequential, main loop)

- [ ] I7.1 Merge T1, T2 (copy files from worktrees); `make test`; `make install`
- [ ] I7.2 Fixture `~/tmp/marked fixtures/img dir/doc.md` (spaced path) with `img.png` beside it, `../up.png`, `sub/a b.svg`, an absolute-path image, `notes.txt` linked as an image, a symlink `evil.png` → a text file, and a missing image. Temporary env-guarded harness (not committed) reads each `<img>`'s `naturalWidth` after load: the four real images > 0; the `.txt`, symlink, and missing ones = 0
- [ ] I7.3 code-reviewer loop until clean (max 5); commit on `s7-images`; tick S7 in `design.md`

## Merge conflicts

- None expected: S7 is the only slice that edits `SchemeHandler.swift` and the serve part of `DocURL.swift`

## Unresolved questions

1. Live reload of images: with the document open, editing `img.png` does not show until the `.md` file itself changes, and maybe not even then (WebKit may reuse the cached image for the same URL). Accept for now (Deferred), or add a cache-busting query (`?v=<mtime>`) in S7?
2. `file://` image URLs in documents: keep blocked (CSP), or allow?
