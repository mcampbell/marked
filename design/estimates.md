# Estimates — Marked clone (2026-10-09)

Scale: trivial/easy/medium/hard = 0.5/1/2/4. Relative within this session.

## Slices

| Slice | Size | Points |
|---|---|---|
| S0 Skeleton: bundle, lifecycle, ready gate, bridge, shell-only handler, `DocURL` encoding, CSP, spikes a/c/d | hard (at ceiling) | 4 |
| S7 Local images: serve rule, MIME, `ImageStamp` cache-busting, image check | medium | 2 |
| S1 Live reload + scroll + banner | medium | 2 |
| S2 Styles | easy | 1 |
| S3 Find (highlight all + count) | medium | 2 |
| S4 Frontmatter | easy | 1 |
| S5 Mermaid | easy | 1 |
| S6 Links | easy | 1 |
| S8 Highlight (`==text==` JS hook) | easy | 1 |
| S10 TOC sidebar: bridge, `TOC` model, `NavigationSplitView`, sidebar spike | medium | 2 |
| S11 Syntax highlight (vendored highlight.js hook + theme) | easy | 1 |
| S12 Print (print op, `@media print`, print spikes) | medium | 2 |
| S13 TOC scroll-spy (message handler, spike) | medium | 2 |
| **Slices total** | | **22.5** |

## Merge conflicts

| Item | Slices | Points |
|---|---|---|
| C1 `.commands` | S2, S3 | 0.5 |
| C2 `userScripts` list | S1, S3, S5, S6, S8 | 0.5 |
| C3 `WebView` coordinator | S2, S3, S6, S7 | 0.5 |
| C4 `ReaderView` | S1, S3 | 0.5 |
| C1 `.commands` (new) | S10, S12 | 0.5 |
| C2 `userScripts` (new) | S10, S11 | 0.5 |
| C3 `WebView` coordinator (new) | S10, S12, S13 | 0.5 |
| C5 `base.css` | S11, S12 | 0.5 |
| **Conflicts total** | | **4** |

## Rework

| Item | Trigger | Points |
|---|---|---|
| R1 scroll-after-hooks ordering check | S1 + S5 landed | 0.5 |
| R2 design gate | S0 spike (a) fails → user decision | unestimated |
| R3 printed syntax colors check | S11 + S12 landed | 0.5 |
| **Rework total** | | **1 firm** (+ R2 gate, unestimated) |

**Grand total: 27.5 firm (22.5 slices + 4 conflicts + 1 rework), plus R2 design gate if spike (a) fails (unestimated).**

S10–S13 add 9.5 (7 slices + 2 conflicts + 0.5 rework).
