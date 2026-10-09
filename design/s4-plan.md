# S4 implementation plan — frontmatter (parallel)

Source: `design.md` (S4 row, "Frontmatter trick", S1 change rule for frontmatter), `grill.md` Q7. Size: 1 pt (`estimates.md`). Builds on `s7-images` (incl. `CMARK_OPT_NOBREAKS`, added after this plan was written: F2 must keep that option and the soft-break tests green).

Done = a document starting with a YAML frontmatter block shows that block verbatim as a monospace code block above the body, in every style; the body renders as before with correct live-scroll line numbers; an edit inside the frontmatter scrolls to the block; `make test` green; live check passes.

## Shape

```
W4 frozen stub + CSS rule (sequential, small)
 ├─ F1 Frontmatter.split + tests (MarkedCore)      ┐ parallel, disjoint files,
 └─ F2 HTMLRenderer integration + tests            ┘ one builder each, own worktree
I4 integrate + live check (sequential)
```

Critical path: W4 → join(F1, F2) → I4.

## Own decisions

- Detection (Q7): line 1 is exactly `---`; the block closes at the first later line that is exactly `---` or `...`. No closing fence → not frontmatter, the whole document renders as markdown (cmark turns the `---` into a thematic break)
- "Exactly" tolerates only what editors add invisibly: a trailing `\r` (CRLF files) and a UTF-8 BOM before line 1. Leading or trailing spaces on a fence line → not a fence
- Display (user, 2026-10-09): lines 1…N verbatim **including both fences** (`---` … `---` or `...`, as written), HTML-escaped (`&`, `<`, `>`, `"`). Empty frontmatter (`---` then `---`) → a block showing the two fences. A `---` anywhere other than line 1 is normal markdown (thematic break or setext underline)
- Line numbers: replace lines 1…N (N = closing fence) with empty lines before cmark, so cmark's `data-sourcepos` stays absolute and S1 needs no frontmatter knowledge (design "Frontmatter trick")
- Output: `<pre class="frontmatter" data-sourcepos="1:1-N:3"><code>…</code></pre>` prepended to cmark's HTML. The `-N:3` end column keeps the attribute in the form `scroll.js` `rangeOf` parses
- Style independence: `base.css` `pre.frontmatter` sets its own font family, size, line height, and background; it reads none of the style variables (`--font`, `--leading`), so S2 style swaps cannot change it
- `ImageStamp` and S8 highlight do not touch it: its text is escaped (no real `<img>`), and S8 skips `pre`/`code`
- No YAML parsing (Rejected, Q7); TOML `+++` stays Deferred

## Frozen contracts (W4)

```swift
// MarkedCore/Frontmatter.swift
public struct Frontmatter: Equatable, Sendable {
    public let text: String       // lines 1…endLine verbatim incl. both fences, joined with "\n", each line minus a trailing "\r", no trailing newline
    public let endLine: Int       // 1-based line of the closing fence
    public init(text: String, endLine: Int)
}
public enum FrontmatterSplit {
    /// nil when the document has no closed frontmatter block.
    public static func split(_ source: String) -> (frontmatter: Frontmatter, body: String)?
    // body = source with lines 1…endLine replaced by empty lines (same line count)
}
```

`HTMLRenderer.render(_:)` keeps its signature.

## File ownership

| File | Owner |
|---|---|
| `Sources/MarkedCore/Frontmatter.swift` (stub), `Resources/base.css` (frontmatter rule) | W4 (frozen after) |
| `Sources/MarkedCore/Frontmatter.swift` (body of `split`), `Tests/MarkedCoreTests/FrontmatterTests.swift` | F1 |
| `Sources/MarkedCore/HTMLRenderer.swift`, `Tests/MarkedCoreTests/HTMLRendererTests.swift` (add tests) | F2 |

## Tasks

### W4 — stub + CSS (sequential, main loop)

- [x] W4.1 Branch `s4-frontmatter` from `s7-images`
- [x] W4.2 `Frontmatter.swift` with the frozen types; `split` → `nil`
- [x] W4.3 `base.css`: `pre.frontmatter { font: 13px/1.4 ui-monospace, Menlo, monospace; background: #eef2f6; border-left: 3px solid #8aa; }` (fixed values, no `var()`)
- [x] W4.4 `make test` green → commit → fork worktrees

### F1 — split (builder)

- [ ] F1.1 Tests first (no `import Foundation`):
  - `"---\ntitle: x\n---\n# H"` → text `"---\ntitle: x\n---"`, endLine 3, body `"\n\n\n# H"`
  - closes with `...` → recognized; text ends with `"..."` (closing fence kept as written)
  - unclosed (`"---\na: 1\n# H"`) → `nil`
  - `---` not on line 1 (`"\n---\na\n---"`) → `nil`
  - fence with trailing space (`"--- \na\n---"`) or indent → `nil`
  - CRLF: `"---\r\na: 1\r\n---\r\n# H"` → text `"---\na: 1\n---"`, endLine 3, body keeps 4 lines
  - BOM: `"\u{FEFF}---\na\n---"` → recognized, text `"---\na\n---"` (BOM not shown)
  - empty block `"---\n---\nx"` → text `"---\n---"`, endLine 2
  - only the first closing fence counts: `"---\na\n---\nb\n---"` → endLine 3
  - multi-line, `<`/`&` in text → returned unescaped (escaping is F2's job)
  - body line count always equals source line count
- [ ] F1.2 Implement: strip one leading BOM; split the **UTF-8 bytes** on LF keeping empties, as `LineDiff` does (`source.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)`, then `String(decoding:as: UTF8.self)` per line; LF never occurs inside a multi-byte character). Never split `String` on `"\n"`: Swift treats CRLF as one `Character`, so the CRLF fixture would become one line and frontmatter would go undetected (reproduced in review, 2026-10-09); trim one trailing `"\r"` per line for comparison only; find the closing fence; build `text` from original lines 1…endLine (minus their `\r`, BOM dropped); `body` = `endLine` empty lines + the remaining original lines, joined with `"\n"`

### F2 — renderer integration (builder)

- [ ] F2.1 Tests first (in `HTMLRendererTests`):
  - frontmatter doc → output starts with `<pre class="frontmatter" data-sourcepos="1:1-3:3"><code>---\ntitle: x\n---</code></pre>`
  - body heading keeps its absolute line: `# H` on line 4 → `data-sourcepos="4:1-4:3"`
  - escaping: `a: <b> & "c"` → `a: &lt;b&gt; &amp; &quot;c&quot;`
  - unclosed → no `class="frontmatter"`, an `<hr` present
  - empty block → `<pre class="frontmatter" data-sourcepos="1:1-2:3"><code>---\n---</code></pre>`, body still at correct lines
  - `---` on line 3 of a plain document → no frontmatter block (normal markdown)
  - CRLF regression: `"---\r\ntitle: x\r\n---\r\n# H\r\n"` → frontmatter block present with `<code>---\ntitle: x\n---</code>`, and `# H` keeps `data-sourcepos="4:1-4:3"`
  - existing tests stay green (incl. the `==` code tests)
- [ ] F2.2 Implement: `FrontmatterSplit.split(source)`; render `body` (or `source` when nil) with the existing cmark code; prepend the block whenever `split` returns one. A small private `escape(_:)` for `& < > "`

### I4 — integrate + live check (sequential, main loop)

- [ ] I4.1 Merge F1 and F2 (copy files); `make test`; `make install`
- [ ] I4.2 Fixture `~/tmp/marked fixtures/fm/doc.md`: 4-line frontmatter (incl. `<tag>` and `&`), then 60 paragraphs. Temporary env-guarded harness (not committed):
  - `pre.frontmatter` exists, its text equals lines 1…N including both fences, computed `font-family` is monospace
  - append at the end → scrolls down (S1 still works with frontmatter)
  - then edit frontmatter line 2 → `scrollY` returns near 0 (target = frontmatter block)
  - unclosed variant → no `pre.frontmatter`, an `hr` at the top
- [ ] I4.3 code-reviewer loop until clean (max 5); commit on `s4-frontmatter`; tick S4 in `design.md`

## Merge conflicts

- None expected: S4 is the only slice that edits `HTMLRenderer.swift`, `Frontmatter.swift`, and the `pre.frontmatter` rule in `base.css`

## Resolved questions (user, 2026-10-09)

1. Show the `---` fences in the block: yes. A `---` found elsewhere is normal markdown

No open questions.
