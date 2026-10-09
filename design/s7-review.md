# S7 code review — round 1

Branch `s7-images`, `a559183..5287d2e`. Date 2026-10-09.

## Overview

Change type: patch (extends the S0 scheme handler and the S1 render closure). Problems: 0 Critical, 0 Major, 1 Minor, 2 Cosmetic. The serve rule, MIME lookup, and cache-busting fit the S0/S1 contracts. 66 Swift + 8 JS tests and the live check pass. Fix the image stamp for symlinked images.

---

## Minor

### m1 Cache-busting ignores symlink targets — `Sources/Marked/WebView.swift` (`mtime`)

Fault: `attributesOfItem` does not follow a final symlink, so `mtime` reads the link, while the handler serves the target. An edit to the target keeps the old `v`, so WebKit can show the cached image. Seen in the live run: `evil.png` carried the link's own mtime.

Fixes:
- Resolve symlinks before the stat. **Fixed.**

## Cosmetic

### c1 Extension parsed twice, from the whole path — `Sources/MarkedCore/DocURL.swift`

Fault: `isImage` and `contentType` each split the full path on `.`. It works (the last piece contains `/` when the file has no extension), but it repeats code and reads as fragile.

Fixes:
- One private `ext(_:)` via `pathExtension`. Guard test added first (`serveExtensionFromFileNameOnly`), green before and after. **Fixed.**

### c2 Stale "W7 stub." doc comments — `Sources/MarkedCore/DocURL.swift`

Fixes:
- Removed. **Fixed.**

## Checked, no problem

- Security: extension checked on the requested and the resolved path (symlink to `notes.txt` refused, live); non-image, missing, and directory paths → 403; no new navigation surface; `file://` stays blocked (CSP).
- Correctness: `ImageStamp` quote-aware scan covers both review regressions; only the first double-quoted `src` of a real `<img>` changes; query and fragment targets left alone.
- Performance: one regex pass per render and one `stat` per local image; images are read whole on the main thread — accepted (document images are small; plan decision).
- Coupling: `DocURL` owns the URL contract, extension set, and MIME; `SchemeHandler` only probes the file system; `ImageStamp` is pure with injected `mtime`.

---

# Round 2 (after fixes)

m1, c1, c2 fixed. 67 Swift + 8 JS tests green, build warning-free. Result: clean.
