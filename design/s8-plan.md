# S8 implementation plan — `==highlight==`

Source: `design.md` (S8 row, "S8 highlight rules", `==` literal-in-code bullet, hook phases), `grill.md` D23, D24. Size: 1 pt (`estimates.md`). Builds on `s6-links`.

Done = `==text==` outside code renders as `<mark>text</mark>` on every render (live reload included); `==` stays literal inside `pre` (code blocks, frontmatter), `code`, `kbd`, `samp`, Mermaid output and raw `script`/`style`/`textarea`; `== x ==` and `====` stay literal; mark text is set with `textContent` (no HTML injection); find matches across `<mark>` boundaries; heading ids (S6) slug the text without `==`; `make test` green; live check passes.

## Shape

```
W8 stub + script line (sequential, main loop)
 └─ K1 js/highlight.js: pure splitter + DOM walk + node tests (one builder)
I8 integrate + live check (sequential, main loop)
```

One stream: 1 pt, one new JS file plus one `userScripts` line. No parallel fork.

## Own decisions

- **Pure core** `splitHighlights(text) -> [{text, mark}]` (adjacent parts, concatenated `text` equals the input minus the `==` delimiters). Regex `/==([^\s=]|[^\s=][\s\S]*?[^\s=])==/g`: the inner text starts and ends with a char that is neither whitespace nor `=`; the one-char branch is tried first and the multi-char branch is lazy, so the shortest match wins (an optional-group form such as `(?:.*?[^\s=])?` is greedy and swallows `==a== and ==b==` whole: checked in node), so `== x ==`, `====` and `=====` stay literal, `==x==` (one char) marks, `==a====b==` gives two marks, `a==b==c` marks `b` mid-word. Text with no `==` returns `[{text, mark: false}]` without running the regex
- **DOM walk (`transform` phase):** one `TreeWalker` over text nodes of `#content` whose `data` contains `==`; reject a node inside `pre, code, kbd, samp, div.mermaid, svg, script, style, textarea` (`closest`). Collect first, then replace each node with a fragment of text nodes and `<mark>` elements built with `textContent`. Same text node only: a highlight that spans inline markup (`==a *b* c==`) stays literal (deferred, design)
- **Phase order:** `transform` hooks run in parallel with Mermaid's. The highlight hook is synchronous and touches only text outside `pre`; Mermaid replaces `pre` blocks and inserts its notes after its first `await`. Disjoint DOM, so registration order does not matter (design)
- **Find and ids:** `find.js` treats `MARK` as inline (not in its block set), so a query matches across the mark edges. `anchors.js` runs in `decorate`, after `transform`, so `# ==Head==` gets the id `head`
- **Style:** the user-agent default for `mark` (D35). No `base.css` change
- **Global names** stay specific (`splitHighlights`, `HIGHLIGHT_RE`, `markHighlights`): all app scripts share one global scope (S5 review m2)

## Frozen contracts (W8)

```js
// Resources/js/highlight.js (app world). Registers Marked.hook("transform", markHighlights).
// Pure, exported for node behind the `typeof module` guard:
//   splitHighlights(text: string) -> Array<{text: string, mark: boolean}>
```

## File ownership

| File | Owner |
|---|---|
| `highlight.js` stub; `userScripts` line in `WebView.swift` | W8 (frozen after) |
| `Resources/js/highlight.js` (body), `Tests/js/highlight.test.mjs` | K1 |

## Tasks

### W8 — stub (sequential, main loop)

- [x] W8.1 Branch `s8-highlight` from `s6-links`
- [x] W8.2 `highlight.js` stub (`splitHighlights` returns `[{text, mark: false}]`, no hook); append `resource("highlight", "js", subdirectory: "js")` to `userScripts`
- [x] W8.3 `make test` + `make app` green → commit

### K1 — highlight.js (builder)

- [ ] K1.1 Node tests first (`Tests/js/highlight.test.mjs`): `a ==b== c` → `a`, mark `b`, `c`; `==x==` → one mark; `==a== and ==b==` → two marks; `==a====b==` → marks `a`, `b`; `a==b==c` → mark `b`; `== x ==`, `====`, `=====`, `==`, `x == y` → one literal part equal to the input; `==a == b==` → one mark `a == b` (pins the lazy rule); `==é 日本==` → one mark; `"==a\nb=="` and `"==a\r\nb=="` (escapes in the test) → one mark with the line break kept (same text node, any line; raw HTML keeps newlines); no `==` → one literal part; empty → `[{text: "", mark: false}]`; for every case the parts joined plus removed delimiters equal the input
- [ ] K1.2 Implement `splitHighlights`
- [ ] K1.3 DOM hook `markHighlights` per "DOM walk"; `<mark>` via `document.createElement("mark")` + `textContent`, literal parts via `document.createTextNode`
- [ ] K1.4 `node --test 'Tests/js/*.test.mjs'` green

### I8 — integrate + live check (sequential, main loop)

- [ ] I8.1 Merge K1; `make test`; `make install`
- [ ] I8.2 Fixture: frontmatter `title: ==fm==`; `# ==Head==`; `a ==plain== b`; `**==bold==**`; `[==link==](#head)`; `` `==code==` ``; fenced code with `if a == b { ==x== }`; raw `<kbd>==k==</kbd>`, `<samp>==s==</samp>`; `== spaced ==`; `====`; `==<b>a</b>==` (spans markup); raw `<b>==x</b>==`; a Mermaid block with node label `==m==`; raw `<script>/* ==s== */</script>` (inert: inserted by `innerHTML`, page JS off); raw `<textarea>==t==</textarea>`; raw HTML block `<p>==multi` newline `line==</p>` (one text node across a line break). Temporary env-guarded harness (not committed):
  - `mark` texts = exactly `Head`, `plain`, `bold`, `link`, `multi\nline` (document order); no `mark` inside `pre`, `code`, `kbd`, `samp`, `div.mermaid`, `script`, `textarea`
  - the code block, inline code, frontmatter, `kbd`, `samp`, spaced and `====` texts still contain their `==`
  - the `h1` id is `head`
  - injection: a fixture line `==<img src=x onerror=1>==` as escaped text (`==&lt;img…&gt;==`) → the mark's `textContent` is the literal `<img …>`, no `img` element created
  - find `plain b` → `1 of 1` (crosses the mark edge); find `==` → counts only the literal `==` occurrences outside marks (no crash)
  - live reload: append `==new==` → marks + 1; no nested `mark` (`mark mark` count 0)
  - ≥ 2 s between launches; `--args -ApplePersistenceIgnoreState YES`
- [ ] I8.3 code-reviewer loop until clean (max 5) → `design/s8-review.md`; tick S8 in `design.md`; commit on `s8-highlight`

## Merge conflicts

- C2 `userScripts`: one line in W8 (already counted in `estimates.md`)

## Deferred

- A highlight spanning inline markup (`==a *b* c==`) (design)
- Backslash-escaped `\==` (cmark removes the backslash before JS sees the text) (design)

## Resolved questions (user, 2026-10-09, D35)

1. `<mark>` color: user-agent default
2. Mid-word `a==b==c`: marks `b`

No open questions.
