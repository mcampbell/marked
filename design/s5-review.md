# S5 code review — rounds 1-2

Branch `s5-mermaid`, `s3-find..HEAD`. Date 2026-10-09.

## Overview

Change type: net new (Mermaid hook, vendored library) plus a small patch (`userScripts`, `base.css`). Round 1: 0 Critical, 0 Major, 2 Minor, 0 Cosmetic, both fixed. Round 2 (the fixes): clean. Diagrams render offline under the real CSP. A bad diagram keeps its source and shows a note, and the other diagrams and later phases still run. 120 Swift + 31 JS tests, the W5 spike, the I5 live check and R1 pass.

---

## Minor

### m1 A multi-line parse error loses its layout — `Resources/base.css`

Fault: Mermaid parse errors are three lines (the excerpt, a `---^` caret line, and "Expecting …"). In a normal `div`, the whitespace collapses, so the caret no longer points at the error. The I5 fixture showed this.

Fixes:
- `.mermaid-error` now uses `white-space: pre-wrap` and a monospace font. **Fixed.**

### m2 Generic global name in the shared script world — `Resources/js/mermaid-hook.js`

Fault: all app scripts and the vendored `mermaid.min.js` run as classic scripts in one `.defaultClient` global scope. A top-level `let counter` throws "duplicate variable" (and so stops the hook from loading) if a later script declares the same name. A `var` or function with the same name silently replaces it.

Fixes:
- Renamed to `mermaidIdSeq`. **Fixed.** Checked: the vendor script adds only `mermaid`, `__esbuild_esm_mermaid_nm` and `injected` (node `vm` run), so there is no clash today with `find.js` (`matchOffsets`, `step`, `locator`) or `scroll.js` (`pickTarget`, `rangeOf`). Keep top-level names specific in S6 and S8.

## Checked, no change

- Security (`mc-code-security`): `securityLevel: "strict"` sanitizes the labels and removes click handlers. The SVG goes in through `innerHTML`, but page JS is off and the hook runs in the isolated world, so script or `on*` attributes in the SVG cannot run. The error note uses `textContent`. No CSP change: SVG inline styles were already allowed. The vendor file is pinned by version and sha256 (`Resources/vendor/VERSION`). `npm pack` checked the registry integrity, and nothing from the package was run.
- Correctness: `renderAll` runs the diagrams one at a time and never rejects (6 node tests). A throw becomes `{error}` at its index. `data-sourcepos` is copied only when it exists. The cleanup removes Mermaid's measuring nodes only when they are outside `#content`. The I5 injected failure (fake `#d<id>` + throw) proves that the cleanup, source retention, the next good diagram, and the later phases work.
- Find: the diagram text is skipped, and the source of a failed diagram and its note stay searchable. With an injected failure, the highlights and the count stay correct.
- Performance: the vendor script adds ~78 ms per window load (W5.4 f). Every render draws every diagram again (`ponytail:` note: cache only if measured slow).
- Error text from Mermaid's `Error.message` is used as is. A non-Error throw falls back to `String(e)` (tested).
