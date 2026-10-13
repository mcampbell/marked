# Marked

A native, read-only Markdown viewer for macOS. Open a `.md` file, keep it open
next to your editor, and the view updates each time you save.

Swift, SwiftUI and WebKit. No Xcode project: Swift Package Manager and a
`Makefile` only.

## Status and license

This is a personal tool. It was never meant for distribution beyond personal
use: there is no notarization, no auto-update, and no support. Do what you want
with it within the terms of the [Apache License 2.0](LICENSE).

Third-party code in `Resources/vendor/` keeps its own license:
Mermaid (MIT, `mermaid.LICENSE`) and highlight.js (BSD-3-Clause,
`highlight.LICENSE`). `Resources/vendor/VERSION` pins each version and its
SHA-256.

## Features

- **GitHub-flavored Markdown**: tables, strikethrough, autolinks and task lists
  (cmark-gfm). Raw HTML renders. A line break in the source with no blank line
  renders as one line.
- **Live reload**: the view updates within about 1 second of a save. It scrolls
  to the first changed block and flashes it. Atomic saves (write to a temp
  file, then rename) work.
- **File errors**: a red banner shows a missing, unreadable or non-UTF-8 file.
  The last good render stays on screen, and the view recovers when the file is
  good again.
- **Styles**: sans (default), serif and mono, with Cmd-1/2/3. The choice
  applies to all windows and stays after a restart.
- **Full width**: text fills the window width. A side margin grows with the
  window, up to a limit. Diagrams also grow with the window, but never past
  their natural size.
- **Text size**: View > Make Text Bigger (Cmd-plus or Cmd-=), Make Text Smaller
  (Cmd-minus) and Actual Size (Cmd-0). Each step is 10% of the normal size,
  from 50% to 300%. Only text changes size: diagrams and images do not. Each
  window has its own size. A new window starts at 100%.
- **Find**: Cmd-F or Ctrl-F opens a find bar. It highlights all hits and shows
  "n of m". Enter or Cmd-G goes to the next hit, Shift-Enter or Shift-Cmd-G to
  the previous one, Esc closes the bar. Matching ignores case and works across
  formatting (for example, a hit that is half bold).
- **Table of contents**: View > Show Sidebar (Ctrl-Cmd-S) lists every heading,
  indented by level. Click a heading to jump to it. While you scroll, the
  sidebar marks the heading you read.
- **Syntax highlighting**: fenced code blocks with a language label
  (` ```swift `, ` ```js `, …) get colors (highlight.js common languages,
  GitHub light theme). Blocks with no label or an unknown label stay plain.
- **Mermaid diagrams**: ` ```mermaid ` blocks render as diagrams, offline. A
  bad diagram shows its source and the error. The other diagrams still render.
- **Highlight marks**: `==text==` renders as highlighted text. Inside code it
  stays literal.
- **Frontmatter**: a `---` block on line 1 shows as a monospace block. The app
  does not parse it.
- **Images**: relative local images load (`img.png`, `../assets/x.png`).
  Remote `https` images load. An edited image shows on the next render of the
  document.
- **Links**: a web link opens in your browser. A link to another `.md` file
  opens it in a new window. A `#heading` link scrolls in the page (headings get
  GitHub-style ids). A link to any other local file reveals that file in
  Finder. The app never opens it.
- **Print and PDF**: File > Print (Cmd-P) opens the macOS print panel. Use
  "PDF > Save as PDF" in that panel to export a PDF. Long code lines wrap, and
  code blocks, diagrams and table rows do not split across pages.
- **Windows**: one window per document. Open a document that is already open,
  and its window comes to the front. The app quits when you close the last
  window.

### Security model

A Markdown file can contain raw HTML, so the viewer treats each document as
untrusted:

- Page JavaScript is off. Only the app's own scripts run, in a separate
  WebKit content world.
- The app serves only image files from the document's folder. It never serves
  other local files to the page.
- A content security policy blocks frames, objects, forms and `<base>`.
- Plain `http:` images do not load (App Transport Security). `https:` images
  load, so a remote image can tell its server that you opened the file.

## Requirements

- macOS 14 or later (built and tested on macOS 26, Apple silicon)
- Swift 6 toolchain: the Xcode Command Line Tools are enough
  (`xcode-select --install`). Xcode is not necessary.
- Optional: Node.js, for the JavaScript tests. `make test` skips them when
  `node` is missing.

## Build and install (no root)

No step needs `sudo` or administrator rights. The app installs into your own
`~/Applications` folder.

```sh
git clone git@github.com:mcampbell/marked.git
cd marked
make test      # Swift tests + JavaScript tests
make install   # build, assemble, sign, copy to ~/Applications/Marked.app
```

The `Makefile` targets:

| Target | What it does |
|---|---|
| `make build` | `swift build -c release` |
| `make test` | Swift tests (with the Command Line Tools framework flags) and `node --test` |
| `make app` | Assembles `build/Marked.app` and signs it ad hoc |
| `make run` | `make app`, then opens the app |
| `make install` | `make app`, copies the app to `~/Applications/Marked.app`, then registers it with Launch Services for your user only |
| `make clean` | Removes `.build/` and `build/` |

The first build fetches one dependency, `swiftlang/swift-cmark`, at a pinned
revision.

### Open files with it

The app registers as an alternate viewer for `.md`, `.markdown` and `.mdown`.
It does not take over as the default app. To use it:

- Finder: right-click a file > Open With > Marked
- Terminal: `open -a Marked README.md`
- To make it the default: select a `.md` file in Finder > Get Info > "Open
  with" > Marked > Change All…

## Signing

`make app` signs the bundle ad hoc: `codesign --force -s -`. An ad-hoc
signature has no identity and no Apple certificate. It is sufficient to run
the app on the Mac that built it:

- Apple silicon runs only signed code. The ad-hoc signature satisfies this.
- An app that you build yourself has no quarantine attribute, so Gatekeeper
  does not check it. It opens with no warning.
- After you change anything inside `Marked.app`, sign it again. `make app` and
  `make install` do this for you.

You do not need an Apple Developer account, a Developer ID certificate or
notarization.

To run a copy on a different Mac, build it on that Mac. If you copy a built app
there (download, AirDrop, chat), macOS adds a quarantine attribute, and
Gatekeeper blocks the app because it is not notarized. To allow it, remove the
attribute:

```sh
xattr -dr com.apple.quarantine ~/Applications/Marked.app
```

Or open the app once, then go to System Settings > Privacy & Security and
click "Open Anyway".

The bundle identifier is `com.example.Marked`. Change it in
`Scripts/Info.plist` if it clashes with another app.

## Project layout

```
Package.swift, Makefile
Scripts/Info.plist          app bundle metadata
Sources/MarkedCore/         pure logic, unit tested (render, diff, find, TOC, URLs)
Sources/Marked/             SwiftUI app, WebKit view, file watcher
Resources/                  page shell, CSS, app JavaScript, vendored libraries
Tests/MarkedCoreTests/      Swift Testing suites
Tests/js/                   node:test suites for the app JavaScript
design/                     design notes and per-feature plans and reviews
```
