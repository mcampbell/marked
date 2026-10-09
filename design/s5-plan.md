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

- **Pin `mermaid@11.17.2`** (latest 11.x on 2026-10-09; design default "latest 11.x"). 12.1.0 exists: see open question 1. Vendored as `Resources/vendor/mermaid.min.js` with `mermaid.LICENSE` (MIT) and a one-line `VERSION` (`mermaid 11.17.2 sha256 <hash>`). Fetch once with `npm pack` into its own scratch dir; never at build or run time
- **Load:** two `userScripts` lines (C2): `vendor/mermaid.min.js`, then `js/mermaid-hook.js`, both `.defaultClient`, like every app script. The hook reads the global `mermaid` only at call time, so the order is not load-bearing
- **Init once:** `mermaid.initialize({startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true})`. Default theme; no tie to S2 fonts (open question 2)
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
| `Resources/vendor/{mermaid.min.js, mermaid.LICENSE, VERSION}`; `userScripts` lines in `WebView.swift`; `base.css` rules; `mermaid-hook.js` stub | W5 (frozen after) |
| `Resources/js/mermaid-hook.js` (body), `Tests/js/mermaid.test.mjs` | K1 |

## Tasks

### W5 — vendor, stubs, spike (sequential, main loop)

- [ ] W5.1 Branch `s5-mermaid` from `s3-find`
- [ ] W5.2 Vendor: `npm pack mermaid@11.17.2` in a new empty scratch dir, `tar -xzf`, copy `package/dist/mermaid.min.js` and `package/LICENSE`; write `VERSION` with the sha256 of the copied file. Do not run anything from the package
- [ ] W5.3 Stub `mermaid-hook.js` (`renderAll` resolves `[]`, no hook registered); append both `userScripts` lines; add the CSS
- [ ] W5.4 Spike in the running app (temporary env-guarded harness, not committed), fixture: one flowchart `A --> B --> C`, one `sequenceDiagram`, one syntax-bad block, one render-bad candidate. From `.defaultClient` call `mermaid.render` directly and record:
  - (a) `typeof mermaid.render === "function"` (the UMD global exists in the isolated world)
  - (b) the flowchart and the sequence diagram render under the real CSP (no `eval` / `unsafe-eval` block; print any thrown message)
  - (c) arrowheads: `takeSnapshot` of the flowchart SVG rect saved as PNG and inspected; the SVG has `<marker>` and `marker-end="url(#…)"`
  - (d) failures: the syntax-bad block throws; find one block that passes `mermaid.parse` but throws in `render` (try a `gantt` with an impossible date, then a `stateDiagram-v2` / `classDiagram` edge case; time box 15 min). None found → the render-bad path is covered by K1's fake-`render` test only; record that
  - (e) leftovers: after each failure and success, list `body > [id^="mmd-"], body > [id^="dmmd-"]`
  - (f) cost: `performance.now()` at the top of `mermaid-hook.js` with vs without the vendor line (3 launches each). Under ~300 ms extra → keep eager injection. Over → stop, ask (open question 3)

  Stop and ask on a CSP block (b) that no `mermaid.initialize` option fixes. Record the results here
- [ ] W5.5 `make test` + `make app` green → commit

### K1 — mermaid-hook.js (builder)

- [ ] K1.1 Node tests first (`Tests/js/mermaid.test.mjs`), fake `render`: all ok → `[{svg}…]` in order; one throws → `{error: msg}` at its index, the rest still `{svg}`; a non-Error throw → `String(e)`; sequential (the fake records start/end; no overlap); ids unique across two `renderAll` calls; empty input → `[]` and no call
- [ ] K1.2 Implement `renderAll`
- [ ] K1.3 DOM layer + hook per "Own decisions": collect blocks, `renderAll` with `mermaid.render` (svg from `{svg}`), apply results, copy `data-sourcepos`, error note via `textContent`, remove leftovers per W5.4 (e); `initialize` once behind the `typeof mermaid` guard
- [ ] K1.4 `node --test 'Tests/js/*.test.mjs'` green

### I5 — integrate + live check (sequential, main loop)

- [ ] I5.1 Merge K1; `make test`; `make install`
- [ ] I5.2 Fixture: a paragraph, a good flowchart with a node label `needle`, a syntax-bad block containing `needle`, the render-bad block from W5.4 (if any), a paragraph `needle` after. Temporary env-guarded harness (not committed):
  - good → `div.mermaid` with `<svg>` and the `<pre>`'s `data-sourcepos`; no `pre code.language-mermaid` left for it
  - bad → `<pre>` kept + `.mermaid-error` text starts with `"Mermaid: "`; the render result `{ok: true, errors: []}`; no `.render-error`
  - no `body > [id^="mmd-"], body > [id^="dmmd-"]` leftovers
  - arrowheads: snapshot PNG of the good diagram, inspected
  - find `needle` → count = 2 (bad source + last paragraph), the diagram label not counted
  - live reload: append a line → diagrams render again, ids increase, still no leftovers
  - **R1:** add 40 filler paragraphs before the diagram, scroll to top, change one line inside the good diagram → after the render the diagram's rect is near the viewport center
  - ≥ 2 s between launches
- [ ] I5.3 code-reviewer loop (+ `mc-code-security` for the SVG insertion) until clean (max 5) → `design/s5-review.md`; tick S5 and R1 in `design.md`; commit on `s5-mermaid`

## Merge conflicts

- C2 `userScripts`: two lines in W5 (already counted in `estimates.md`)
- No Swift renderer change → no S4 conflict (design)

## Deferred

- Diagram theme following S2 styles or dark mode
- Render cache (see `ponytail:` note)
- Lazy injection of the vendor script (only if W5.4 (f) is slow)

## Open questions

1. Pin 11.17.2 (design default, D19 behavior was checked on 11.x) or the new major 12.1.0? Recommend 11.17.2
2. Default Mermaid theme, no S2 font tie-in? Recommend yes
3. If the vendor script adds more than ~300 ms per window load: accept, or lazy-inject on the first Mermaid block (+0.5 pt)? Recommend: decide after W5.4 (f)
