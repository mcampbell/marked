# Marked

Native, read-only Markdown viewer for macOS (Swift 6, SwiftUI, WebKit). SwiftPM + `Makefile`, no Xcode. See `README.md`.

## Knowledge bundle

`.okf/` (gitignored, local only) is an OKF bundle of this repo: architecture, one concept per component, every decision, runbooks. Read `.okf/index.md` first when it exists. After a change, update the touched concepts and `.okf/log.md`; regenerate decisions with `python3 -I .okf/tools/gen_decisions.py` (from the repo root).

## Commands

- `make test` — Swift Testing + `node --test Tests/js`. Plain `swift test` fails under the Command Line Tools
- `make install` — build, ad-hoc sign, copy to `~/Applications/Marked.app`, register
- No `sudo`, no System Settings or Accessibility changes (work machine)

## Layout

- `Sources/MarkedCore/` — pure logic, unit tested. Put new logic here first (TDD)
- `Sources/Marked/` — app target, no unit tests; verify with a temporary env-guarded harness in `AppDelegate`, removed before commit
- `Resources/` — shell, CSS, app JS hooks, `vendor/` (pinned). Loaded via `Bundle.main`, not SwiftPM resources
- `design/` — `design.md` (design), `grill.md` (decision log Q1–Q13, D14+; D overrides Q), `<id>-plan.md`, `estimates.md`

## Rules

- Page JS stays off. App JS runs only in the `.defaultClient` world. Features add `Marked.hook(phase, fn)`; never edit `marked.js` for a feature
- `marked://doc/` serves images only; keep the CSP in `shell.html` as is
- Each feature: next `Dnn` line in `design/grill.md`, README feature line, points row in `design/estimates.md`
- Commits: `scope: description (Dnn)`, no co-author trailer. Merge with `--no-ff` (`Merge <branch>: …`)
- US English in prose, comments, commits
