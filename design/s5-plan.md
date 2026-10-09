# S5 implementation plan — Mermaid

Source: `design.md` (S5 row, "Mermaid" bullet, hook phases, R1, C2), `grill.md` Q12, D19. Size: 1 pt + R1 0.5 pt (`estimates.md`). Builds on `s3-find`.

Done = a ` ```mermaid ` block renders as a diagram, offline, from a vendored, pinned `mermaid.min.js`; flowchart arrowheads show; a bad diagram (parse or render failure) keeps its source and shows an error note in place while the other diagrams still render and later hook phases still run (`{ok: true}`, no `.render-error`); no Mermaid temp nodes leak into `<body>`; find skips diagram text but finds text in a failed diagram's source; R1: an edit inside a diagram scrolls to that diagram; `make test` green; live check passes.

## Shape

```
W5 vendor + stubs + spike (sequential, main loop)
 └─ K1 js/mermaid-hook.js: pure sequential renderer + DOM layer + node tests (one builder)
I5 integrate + live check + R1 (sequential, main loop)
```

One stream: the slice is 1 pt and every file but one line of `WebView` is new. No parallel fork.

## Own decisions

- **Pin `mermaid@11.17.2`** (latest 11.x on 2026-10-09; D33: not 12.x). Vendored as `Resources/vendor/mermaid.min.js` with `mermaid.LICENSE` (MIT) and a one-line `VERSION` (`mermaid 11.17.2 sha256 <hash>`). Fetch once with `npm pack` into its own scratch dir; never at build or run time
- **Load:** two `userScripts` lines (C2): `vendor/mermaid.min.js`, then `js/mermaid-hook.js`, both `.defaultClient`, like every app script. The hook reads the global `mermaid` only at call time, so the order is not load-bearing
- **Init once:** `mermaid.initialize({startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true})`. Default theme; no tie to S2 fonts (D33)
- **Hook (`transform` phase):** for each `#content pre > code.language-mermaid`, in document order, **sequentially** (D19, one temp id at a time): `const {svg} = await mermaid.render(id, code.textContent)`. Success → replace the `<pre>` with `<div class="mermaid" data-sourcepos="…copied from pre…">` + svg. Failure (parse or render, any throw) → keep the `<pre>`, insert after it `<div class="mermaid-error">` with `"Mermaid: " + message` set through `textContent`. The hook never throws for a bad diagram, so a bad diagram is not a hook failure (design: "Expected Mermaid failures stay inside S5's own fallback")
- **Ids:** module counter, `mmd-<n>`, unique across renders. After each `render` (success or failure) remove any leftover `#<id>` / `#d<id>` outside `#content` (Mermaid's measuring nodes; the spike confirms which remain on 11.17.2)
- **Pure core, injected IO** (like `RenderQueue`): `renderAll(sources, render) -> Promise<Array<{svg} | {error}>>` runs `render(id, src)` one at a time and maps each throw to `{error: message}` (`String(e)` for a non-Error). The DOM layer only collects sources and applies results. Node tests cover the core with a fake `render`
- **Security:** `strict` sanitizes labels and drops click handlers; page JS is off, so script or `on*` attributes in the SVG cannot run either. The error note uses `textContent`, never `innerHTML`. CSP already allows inline styles for the SVG (`style-src 'unsafe-inline'`); no CSP change
- **No cache:** every render re-renders every diagram. `ponytail:` comment in the hook: cache source → svg if a measured render gets slow
- **Find:** `find.js` already skips `div.mermaid` and `svg`; the `<pre>` and the error note of a failed diagram stay searchable
- **Scroll (R1):** `position` runs after `transform`, and the wrapper keeps `data-sourcepos`, so S1 scroll targets the diagram. S1 has landed, so S5 runs the joint check (I5)

## Frozen contracts (W5)

```js
// Resources/js/mermaid-hook.js (app world). Registers Marked.hook("transform", renderMermaid).
// Pure, exported for node behind the `typeof module` guard (as scroll.js):
//   renderAll(sources: string[], render: (id, src) => Promise<string>) -> Promise<Array<{svg: string} | {error: string}>>
//   sequential: the next render starts only after the previous one settles; ids "mmd-<n>", never reused
```

```css
/* Resources/base.css (W5) */
div.mermaid { text-align: center; margin: 1em 0 }
.mermaid-error { color: #c00; font-size: .9em; margin: -.5em 0 1em }
```

## File ownership

| File | Owner |
|---|---|
| `Resources/vendor/{mermaid.min.js, mermaid.LICENSE, VERSION}`; `userScripts` lines in `WebView.swift`; `base.css` rules; `mermaid-hook.js` stub incl. `initialize` | W5 (frozen after) |
| `Resources/js/mermaid-hook.js` (body), `Tests/js/mermaid.test.mjs` | K1 |

## Tasks

### W5 — vendor, stubs, spike (sequential, main loop)

- [x] W5.1 Branch `s5-mermaid` from `s3-find`
- [x] W5.2 Vendor: `npm pack mermaid@11.17.2` in a new empty scratch dir, `tar -xzf`, copy `package/dist/mermaid.min.js` and `package/LICENSE`; write `VERSION` with the sha256 of the copied file. Do not run anything from the package
- [x] W5.3 Stub `mermaid-hook.js`: the real `mermaid.initialize({…})` call from "Init once" behind the `typeof mermaid` guard (frozen, so the W5.4 spike runs under the production options), `renderAll` resolves `[]`, no hook registered; append both `userScripts` lines; add the CSS
- [x] W5.4 Spike in the running app (temporary env-guarded harness, not committed), fixture: one flowchart `A --> B --> C`, one `sequenceDiagram`, one syntax-bad block, one render-bad candidate. From `.defaultClient` call `mermaid.render` directly and record:
  - (a) `typeof mermaid.render === "function"` (the UMD global exists in the isolated world)
  - (b) the flowchart and the sequence diagram render under the real CSP (no `eval` / `unsafe-eval` block; print any thrown message)
  - (c) arrowheads: `takeSnapshot` of the flowchart SVG rect saved as PNG and inspected; the SVG has `<marker>` and `marker-end="url(#…)"`
  - (d) failures: the syntax-bad block throws; find one block that passes `mermaid.parse` but throws in `render` (try a `gantt` with an impossible date, then a `stateDiagram-v2` / `classDiagram` edge case; time box 15 min). None found → record that; the I5 injected-failure check covers the full DOM path either way
  - (e) leftovers: after each failure and success, list `body > [id^="mmd-"], body > [id^="dmmd-"]`
  - (f) cost: `performance.now()` at the top of `mermaid-hook.js` with vs without the vendor line (3 launches each). Under ~300 ms extra → keep eager injection. Over → the author picks eager or lazy injection (lazy: +0.5 pt) and records the choice and numbers in "Resolved questions" (D33)

  Stop and ask on a CSP block (b) that no `mermaid.initialize` option fixes. Record the results here

  **Results (2026-10-09, macOS 26 WebKit, real CSP, production `initialize`):** (a) `mermaid` object, `render` function. (b) flowchart 12 343 B and sequence 22 354 B SVG, no CSP error. (c) SVG has `<marker>` and `marker-end="url(#…)"`; snapshot PNG shows the arrowheads. (d) syntax-bad throws in `parse` and `render` ("Parse error on line 3: ...edle] --> B  B --> --> C ---^ Expecting …": the excerpt quotes ~20 chars before the error, so keep `needle` well away from the error line). Render-bad (parse ok, render throws): gantt `2024-13-45` → "Invalid date:2024-13-45"; subgraph cycle `X`⊃`Y`⊃`X` → "Setting Y as parent of X would create a cycle". `gantt … after zz` and subgraph-named-as-node render fine. (e) no `body > #mmd-*` / `#dmmd-*` leftovers after any success or failure (Mermaid cleans up; the hook cleanup stays as a guard, exercised by the I5 injected failure). (f) hook script start 79-80 ms with the vendor script vs 2 ms without (3 launches each): ~78 ms extra → **eager injection kept**
- [x] W5.5 `make test` + `make app` green → commit

### K1 — mermaid-hook.js (builder)

- [x] K1.1 Node tests first (`Tests/js/mermaid.test.mjs`), fake `render`: all ok → `[{svg}…]` in order; one throws → `{error: msg}` at its index, the rest still `{svg}`; a non-Error throw → `String(e)`; sequential (the fake records start/end; no overlap); ids unique across two `renderAll` calls; empty input → `[]` and no call
- [x] K1.2 Implement `renderAll`
- [x] K1.3 DOM layer + hook per "Own decisions": collect blocks, `renderAll` with `mermaid.render` (svg from `{svg}`), apply results, copy `data-sourcepos`, error note via `textContent`, remove leftovers per W5.4 (e) (`initialize` is already in place from W5.3)
- [x] K1.4 `node --test 'Tests/js/*.test.mjs'` green

### I5 — integrate + live check (sequential, main loop)

- [x] I5.1 Merge K1; `make test`; `make install`
- [x] I5.2 (2026-10-09: all pass. 2 rendered with their `data-sourcepos` `5:1-9:3`, `11:1-14:3`; syntax-bad + `Invalid date:2024-13-45` keep `<pre>` + note; no `.render-error`; no leftovers; arrowhead PNG checked; find `needle` 1 of 2; injected failure → "Mermaid: injected" after its `<pre>`, next diagram still renders, fake `#d<id>` removed, find 1 of 2 with 2 live highlights, ids `mmd-0,1` → `mmd-5`; R1: scrollY 0 → 1514, diagram center 290 of 418, re-rendered with `D`. Relaunches need `--args -ApplePersistenceIgnoreState YES`, else window restoration reopens old fixtures) Fixture: a paragraph, a good flowchart with a node label `needle`, a syntax-bad block with `needle` only on a valid line before the error line (`flowchart TD` / `  A[needle] --> B` / `  B --> --> C`), the render-bad block from W5.4 (if any), a paragraph `needle` after. Temporary env-guarded harness (not committed):
  - good → `div.mermaid` with `<svg>` and the `<pre>`'s `data-sourcepos`; no `pre code.language-mermaid` left for it
  - bad → `<pre>` kept + `.mermaid-error` text starts with `"Mermaid: "`; the render result `{ok: true, errors: []}`; no `.render-error`
  - no `body > [id^="mmd-"], body > [id^="dmmd-"]` leftovers
  - arrowheads: snapshot PNG of the good diagram, inspected
  - **injected render failure** (full hook path, independent of W5.4 (d)): the fixture also has a block with the comment line `%% fail` placed **before** the good flowchart. The harness wraps `mermaid.render` in `.defaultClient`: for a source containing `%% fail` it appends a fake measuring node `<div id="d<id>">` to `<body>` and throws `Error("injected")`; all else delegates. Trigger a render (append a line). Then: that block's `<pre>` kept + `.mermaid-error` "Mermaid: injected"; the good flowchart after it still renders; later phases ran (find `.state` count updated, no `.render-error`, `{ok: true}`); the fake `#d<id>` is gone
  - find `needle` → count = 2 (bad source + last paragraph), the diagram label not counted. Precondition, checked first: no `.mermaid-error` text contains `needle` (Mermaid parse errors quote the failing line); if one does, move `needle` further from the error line, not the expected count
  - live reload: append a line → diagrams render again, ids increase, still no leftovers
  - **R1:** add 40 filler paragraphs before the diagram, scroll to top, change one line inside the good diagram → after the render the diagram's rect is near the viewport center
  - ≥ 2 s between launches
- [x] I5.3 (2 rounds, `design/s5-review.md`) code-reviewer loop (+ `mc-code-security` for the SVG insertion) until clean (max 5) → `design/s5-review.md`; tick S5 and R1 in `design.md`; commit on `s5-mermaid`

## Merge conflicts

- C2 `userScripts`: two lines in W5 (already counted in `estimates.md`)
- No Swift renderer change → no S4 conflict (design)

## Deferred

- Diagram theme following S2 styles or dark mode
- Render cache (see `ponytail:` note)
- Lazy injection of the vendor script (only if W5.4 (f) is slow)

## Resolved questions (user, 2026-10-09, D33)

1. Pin 11.17.2, not 12.1.0
2. Default Mermaid theme, no S2 font tie-in
3. Eager vs lazy injection: **eager** (author, after W5.4 (f): ~78 ms extra per window load)

No open questions.
