# S8 code review — rounds 1-2

Branch `s8-highlight`, `s6-links..HEAD`. Date 2026-10-09.

## Overview

Change type: net new (`js/highlight.js`) plus one `userScripts` line. Round 1: 0 Critical, 0 Major, 0 Minor, 1 Cosmetic, fixed. Round 2: clean. Marks appear only outside code. The mark text is set as text, never as markup, and find and heading ids work across marks. 126 Swift + 64 JS tests and the I8 live check pass.

---

## Cosmetic

### c1 Fallback that never runs in `splitHighlights` — `Resources/js/highlight.js`

Fault: `return parts.length ? parts : [{text, mark: false}]`. Input with `==` and no match always pushes the whole text as one literal part, so `parts` is never empty there.

Fixes:
- `return parts;`. **Fixed.** 64 JS tests stay green, and the invariant helper still reassembles every case.

## Checked, no change

- Regex `/==([^\s=]|[^\s=][\s\S]*?[^\s=])==/g`: the one-char branch comes first and the multi-char branch is lazy. The tests pin the separate and adjacent marks, mid-word marks, LF and CRLF line breaks, and the literal cases (`== x ==`, `====`, `=====`).
- Security: marks are built with `createElement("mark")` and `textContent`, and literal parts with `createTextNode`. There is no `innerHTML`. An escaped `<img onerror>` stays as text (live check: 0 `img`). Raw `<script>` text stays untouched.
- Exclusions: `closest("pre, code, kbd, samp, div.mermaid, svg, script, style, textarea")` (live check). The Mermaid notes and `.render-error` boxes are inserted after this hook runs, so it never edits them.
- Phases: the hook is synchronous in `transform`, and Mermaid edits its blocks only after its first `await`, so their DOM does not overlap. `anchors.js` (`decorate`) slugs `# ==Head==` as `head`. Find treats `MARK` as inline, so `plain b` matches across the mark edge.
- Performance: the TreeWalker accepts only text nodes that contain `==`. The nodes are collected before they are replaced.
