# S11 review — Syntax highlight

Change type: net new (S11 slice on top of S0–S8). Branch `s11-syntax`. Reviewer: code-reviewer skill (context, correctness, performance, idioms, security), serial, 2 rounds.

Overview: Round 1 found 0 Critical, 0 Major, 2 Minor, 1 Cosmetic. Both Minor problems are fixed. Round 2 found no problems. Highlight output comes only from the escaped highlight.js value. The app host serves 2 files and gives 403 for all other paths.

---

## Round 1

### Minor

- `Tests/js/syntax.test.mjs`: no test pins that a hostile `className` (raw HTML `<code class="language-__proto__">`) stays plain. The `className` comes from the document, a trust boundary. A probe showed that hljs 11.12.0 returns `null` for `__proto__`, `constructor`, `toString`, `hasOwnProperty`, because its language maps have no prototype.
  - Fixes: add the "prototype key plain" tests. Done.
- `Resources/base.css:7`: `pre code.hljs` has the same specificity as the rule in `hljs-github.css`. It wins only because `shell.html` links `base.css` second. A reorder of the links breaks the `pre` box with no error.
  - Fixes: add a short "why" comment at the rule. Done. (Option not taken: raise the specificity. The rule order is already fixed in `shell.html`.)

### Cosmetic (accepted, no change)

- `Resources/js/syntax.js` `colorCode`: raw-HTML `<pre><code class="language-js"><b>x</b></code></pre>` loses the inline `<b>`. The hook re-highlights from `textContent`. This is safe (no HTML injection), and a raw HTML code block with inline markup and a language class is rare. Keep it.
- `Sources/MarkedCore/DocURL.swift`: the tuple type `(name:ext:subdirectory:)` occurs twice, on adjacent lines. A `typealias` adds a name for one use. Keep it.

### Checked, no problem

- Correctness: `codeLangOf` takes the first `language-` class and makes it lowercase. Unknown, unlabeled and `mermaid` fences stay plain (node tests + live check). `<pre>` keeps `data-sourcepos`. Each render replaces `#content`, so no fence gets a second highlight.
- Concurrency: the `transform` phase runs Mermaid in parallel with this hook. The DOM areas do not overlap: Mermaid uses only `language-mermaid`, and this hook skips it.
- Security (mc-code-security points): `innerHTML` gets only `hljs.highlight(...).value`, which hljs escapes. Tests prove `<script>`/`<img>` input under `html` and `swift` comes back as text. The live check finds no `script`/`img` element in `#content`. `DocURL.appFile` allows exactly `/base.css` and `/hljs.css` on host `app`, and tests reject other paths. The CSP did not change.
- Performance: the hook highlights every fence on every render (a `ponytail:` comment marks this). Script-start cost of the vendor bundle: 94/99/156 ms with it vs 125/135/125 ms without (3 launches each). The difference is not measurable over launch noise, so eager injection stays.
- Idioms: the global names `codeLangOf`, `syntaxHTML`, `colorCode` and `hljs` do not clash with other app scripts (grep + live `typeof` check).

## Round 2

No problems.
