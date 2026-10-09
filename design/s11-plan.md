# S11 implementation plan — Syntax highlight

Source: `design.md` (S11 row, "S11 syntax rules", Security, hook phases, C2, C5, R3), `grill.md` D38, D42, D45. Size: 1 pt (`estimates.md`). Builds on `s10-s13-design` (= `main` + S10–S13 design docs).

Done = a ` ```lang ` fence whose language highlight.js knows (aliases too) shows GitHub-light token colors in all three styles, offline, from a vendored, pinned common bundle; unlabeled, unknown, and `mermaid` fences stay plain; source text never becomes HTML; `<pre>` keeps its `data-sourcepos` and box; find matches across token spans; `marked://app/` serves exactly `base.css` + `hljs.css` (else 403); `make test` green; live check passes.

## Shape

```
W11 vendor + stubs + app-host route (sequential, main loop)
 └─ K1 js/syntax.js: pure core + DOM hook + node tests (one builder)
I11 integrate + live check (sequential, main loop)
```

One stream: 1 pt, all new files except one `SchemeHandler` line, one `shell.html` line, two `userScripts` lines, one `base.css` rule.

## Own decisions

- **Pin `highlight.js@11.12.0`** (`npm view highlight.js version` and `npm view @highlightjs/cdn-assets version` both → `11.12.0`, 2026-10-09). Source: npm package `@highlightjs/cdn-assets@11.12.0` (the prebuilt CDN release; `highlight.min.js` = common bundle, `styles/github.min.css`, `LICENSE` BSD-3-Clause). Tarball `https://registry.npmjs.org/@highlightjs/cdn-assets/-/cdn-assets-11.12.0.tgz`. Fetch once with `npm pack` into its own empty scratch dir; never at build or run time; run nothing from the package
- **Vendor files:** `Resources/vendor/highlight.min.js`, `Resources/vendor/hljs-github.css` (copy of `styles/github.min.css`), `Resources/vendor/highlight.LICENSE`. `VERSION` gains two lines: `highlight.js 11.12.0 highlight.min.js sha256 <hash>`, `highlight.js 11.12.0 hljs-github.css sha256 <hash>` (mermaid line unchanged)
- **App-host route moves to `MarkedCore`** so the 403 rule is tested: `DocURL.appFile(for url: URL) -> (name: String, ext: String, subdirectory: String?)?`: host `app` + path `/base.css` → `("base", "css", nil)`; `/hljs.css` → `("hljs-github", "css", "vendor")`; anything else → `nil` (403). `SchemeHandler` replaces its `/base.css` check with this lookup, loads both files once at init (as `css` today). Touches `DocURL` (not in the design row; one function + tests)
- **Link order:** `shell.html` links `marked://app/hljs.css` **before** `base.css`. Both files use `pre code.hljs` (same specificity), so the later file wins: `base.css` `pre code.hljs { background: none; padding: 0 }` keeps the `pre` box (#f4f4f4, `.75em`) in all styles. CSP already allows `style-src marked:`; no CSP change
- **Load:** two `userScripts` lines (C2) after `highlight`: `vendor/highlight.min.js`, then `js/syntax.js`. The hook reads the global `hljs` at call time, so order is not load-bearing, but keep vendor first
- **Hook (`transform` phase), pure core + thin DOM layer:**
  - `codeLangOf(className) -> string | null`: first `language-<x>` class (`/(?:^|\s)language-(\S+)/`), lowercased; else `null`
  - `syntaxHTML(hljs, className, text) -> string | null`: `lang = codeLangOf(className)`; `null`, `"mermaid"`, or `!hljs.getLanguage(lang)` → `null` (leave plain); else `hljs.highlight(text, {language: lang, ignoreIllegals: true}).value`
  - DOM hook `colorCode`: each `#content pre > code`, `html = syntaxHTML(hljs, code.className, code.textContent)`; non-null → `code.innerHTML = html`, `code.classList.add("hljs")`. Synchronous
- **Safety:** only highlight.js's escaped `.value` is assigned; never source text as HTML (Security). No `highlightElement` (it warns and reads `innerHTML`)
- **Errors:** no try/catch. `ignoreIllegals` + the `getLanguage` guard leave no expected throw; any throw is a bug and shows as a `.render-error` per the S0 contract
- **Phase order:** `transform` runs in parallel with Mermaid (only `language-mermaid`, skipped here) and S8 (never inside `code`). Disjoint DOM
- **Scroll / find:** `<pre>` untouched, keeps `data-sourcepos`. `find.js` joins text per block and `PRE` is a block → a query matches across token `<span>`s. No change to either
- **Global names** specific (shared `.defaultClient` scope, S5 review m2): `codeLangOf`, `syntaxHTML`, `colorCode`; the vendor bundle adds `hljs`. W11 checks no clash
- **Cost:** highlight runs on every render, no cache. `ponytail:` comment in the hook: cache per fence text if a measured render gets slow (large-file perf deferred, design)
- **Node test loads the real bundle** (`createRequire` on `vendor/highlight.min.js`), so alias, escaping, and unknown-language cases test the pinned version, not a fake. If the bundle does not set `module.exports` under node (W11.4), load it with `vm.runInNewContext(src, ctx)` and read `ctx.hljs`

## Frozen contracts (W11)

```js
// Resources/js/syntax.js (app world). Registers Marked.hook("transform", colorCode).
// Pure, exported for node behind the `typeof module` guard:
//   codeLangOf(className: string) -> string | null
//   syntaxHTML(hljs, className: string, text: string) -> string | null   // null = leave plain
```

```swift
// Sources/MarkedCore/DocURL.swift
public static func appFile(for url: URL) -> (name: String, ext: String, subdirectory: String?)?
```

```css
/* Resources/base.css (W11) */
pre code.hljs { background: none; padding: 0 }
```

## File ownership

| File | Owner |
|---|---|
| `Resources/vendor/{highlight.min.js, hljs-github.css, highlight.LICENSE, VERSION}`; `DocURL.appFile` + tests; `SchemeHandler` route; `shell.html` link; `base.css` rule; `userScripts` lines; `syntax.js` stub | W11 (frozen after) |
| `Resources/js/syntax.js` (body), `Tests/js/syntax.test.mjs` | K1 |

## Tasks

### W11 — vendor, stubs, route (sequential, main loop)

- [ ] W11.1 Branch `s11-syntax` from `s10-s13-design`
- [ ] W11.2 Vendor: `npm pack @highlightjs/cdn-assets@11.12.0` in a new empty scratch dir, `tar -xzf`, copy `package/highlight.min.js`, `package/styles/github.min.css` → `hljs-github.css`, `package/LICENSE` → `highlight.LICENSE`; append the two `VERSION` lines with sha256 of the copied files
- [ ] W11.3 Tests first (`DocURLTests`): `appFile` for `marked://app/base.css` → base; `/hljs.css` → vendor `hljs-github.css`; `/other.css`, `/vendor/hljs-github.css`, `/js/syntax.js`, `/`, `marked://doc/…/base.css` → `nil`. Implement `appFile`; switch `SchemeHandler` to it
- [ ] W11.4 Node load check: `node -e` with `createRequire` on the vendor file → `typeof hljs.highlight === "function"` and `hljs.getLanguage("swift")` truthy. Record which load path works (see "Node test loads the real bundle")
- [ ] W11.5 Stub `syntax.js`: `codeLangOf` / `syntaxHTML` return `null`, no hook; `shell.html` `<link rel="stylesheet" href="marked://app/hljs.css">` before the `base.css` link; `base.css` rule; append both `userScripts` lines
- [ ] W11.6 Global-name check in the running app (temporary env-guarded harness, not committed): from `.defaultClient`, `typeof hljs.highlight === "function"`, `typeof Marked.render === "function"`, `typeof splitHighlights === "function"`, `typeof renderAll === "function"`; `document.styleSheets` includes `marked://app/hljs.css`. Also time the script start with vs without the vendor line (3 launches each, as S5 W5.4 f); record the numbers
- [ ] W11.7 `make test` + `make app` green → commit

### K1 — syntax.js (builder)

- [ ] K1.1 Node tests first (`Tests/js/syntax.test.mjs`, real vendored `hljs`):
  - `codeLangOf`: `"language-swift"` → `swift`; `"language-JS"` → `js`; `"foo language-ts bar"` → `ts`; `"language-a language-b"` → `a`; `""`, `"lang-x"`, `"xlanguage-y"` → `null`
  - `syntaxHTML`: `language-swift` `let x = 1` → contains `hljs-keyword`, and the HTML with tags stripped and entities decoded equals the input; alias `language-js` and `language-sh` → non-null; `language-mermaid` → `null`; `language-nosuchlang` → `null`; `""` → `null`
  - injection: `language-html` `<script>alert(1)</script><img src=x onerror=1>` → output has no `<script` and no `<img`; with `</?span[^>]*>` tags removed it has no `<` at all, and decoding entities gives back the input exactly (hljs splits `&lt;` from the tag name with a `hljs-name` span, so no `&lt;script` substring check); same text under `language-swift` (illegal input, `ignoreIllegals`) → escaped, no throw
- [ ] K1.2 Implement `codeLangOf`, `syntaxHTML`
- [ ] K1.3 DOM hook `colorCode` per "Own decisions"; register in `transform`; `ponytail:` cost comment
- [ ] K1.4 `node --test 'Tests/js/*.test.mjs'` green

### I11 — integrate + live check (sequential, main loop)

- [ ] I11.1 Merge K1; `make test`; `make install`
- [ ] I11.2 Fixture: a ` ```swift ` fence with `let needle = 1`; ` ```JS ` (uppercase alias); ` ```sh `; ` ```nosuchlang `; an unlabeled fence; a ` ```mermaid ` flowchart; a ` ```html ` fence with `<script>alert(1)</script>` and `<img src=x onerror=1>`; inline `` `let x = 1` ``; 40 filler paragraphs before a last ` ```swift ` fence. Temporary env-guarded harness (not committed), `open -n … --args -ApplePersistenceIgnoreState YES`, ≥ 2 s between launches, window picked by `webView.url?.path`:
  - `code.hljs` count = 5 (swift, JS, sh, html, last swift); the `nosuchlang`, unlabeled, and inline code have no `.hljs` and no `span`
  - Mermaid fence → `div.mermaid` with `<svg>`, no `.hljs`
  - injection: no `script` or `img` element inside `#content`; the html fence's `textContent` equals its source
  - every highlighted `pre` keeps its `data-sourcepos`; `getComputedStyle(pre).backgroundColor` = `rgb(244, 244, 244)`; `code.hljs` background transparent, padding `0px`
  - color: `getComputedStyle` of the swift fence's first `.hljs-keyword` = github's keyword color (read the value from `hljs-github.css`, do not hard-code)
  - all three styles (Cmd-1/2/3 via `NSApp.postEvent`): same `.hljs` count, keyword color unchanged
  - find `needle = 1` → `1 of 1` (crosses token spans)
  - live reload: change one line inside the last swift fence → still highlighted, its `textContent` equals the new source (no double escaping), scroll lands on that fence (S1)
  - result `{ok: true, errors: []}`, no `.render-error`
- [ ] I11.3 code-reviewer + mc-code-security loop until clean (max 5) → `design/s11-review.md`; tick S11 in `design.md`; if S12 has landed, run R3 (print a highlighted fence to PDF → token colors + `pre` background show); commit on `s11-syntax`

## Merge conflicts

- C2 `userScripts`: two lines in W11 (counted in `estimates.md`)
- C5 `base.css`: one rule in W11; S12 adds `@media print` (counted)

## Deferred

- Auto-detect for unlabeled fences; languages beyond the common bundle (design)
- Highlight cost on huge fences (large-file perf, design)

## Unresolved questions

None. Resolved 2026-10-09 (author, D46):
1. ~~`DocURL.appFile` in `MarkedCore`?~~ Yes: pure + tested; design.md S11 touch list updated
2. ~~Multi-line `VERSION` vs one per vendor?~~ One multi-line `VERSION` file
