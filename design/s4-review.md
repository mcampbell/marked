# S4 code review — round 1

Branch `s4-frontmatter`, `aed8045..792a3da`. Date 2026-10-09.

## Overview

Change type: patch (extends `HTMLRenderer` and `base.css` inside the S0/S1 contracts). Problems: 0 Critical, 0 Major, 0 Minor, 2 Cosmetic. Detection, escaping, line numbers, and style independence work; 87 Swift + 8 JS tests and the live check pass.

---

## Cosmetic

### c1 Stale "W4 stub." doc comment — `Sources/MarkedCore/Frontmatter.swift`

Fixes:
- Removed. **Fixed.**

### c2 Unnamed contract between the block's `data-sourcepos` and `scroll.js` — `Sources/MarkedCore/HTMLRenderer.swift`

Fault: the `1:1-N:3` form exists only so `rangeOf` in `scroll.js` can parse it; nothing at the write site says so (shotgun-surgery coupling).

Fixes:
- One-line comment at the write site naming `scroll.js` `rangeOf`. **Fixed.**

## Checked, no change

- Line splitting now appears in `LineDiff` and `FrontmatterSplit` (both UTF-8 byte split on LF, CRLF-safe). Two uses with different outputs (byte slices vs `String`s): no shared helper yet; extract on a third use.
- Performance: `split` decodes every line of every document, even without frontmatter. No evidence of cost (one call per render, documents are small); no change until measured.
- Security: the block text is escaped (`& < > "`), so raw HTML in frontmatter cannot render; `ImageStamp` and S8 cannot see a real `<img>` in it.
- CSS: `pre.frontmatter` uses fixed `font`/`line-height` and no `var()`, so S2 style swaps cannot change it.
- Correctness: BOM, CRLF, `...` close, first-close-wins, empty block, unclosed, and `---` not on line 1 are all pinned by tests; the live check confirms scroll into the block and an `hr` for an unclosed fence.

---

# Round 2 (after fixes)

c1 and c2 fixed. Tests green. Result: clean.
