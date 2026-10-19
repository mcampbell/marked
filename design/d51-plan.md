# D51 plan: text size on the titlebar

Done = tests green, code-reviewer pass clean, committed on `text-size-title`.

Single slice (one deployable unit, no slicing). No merge conflicts, no rework.

## Decisions (mine)

- Where: window subtitle (`navigationSubtitle`, already in titlebar, already holds failures). Title itself is owned by `DocumentGroup` → no NSWindow title hack
- Text: `120%`. Hidden at 100%. First in subtitle, before failures (`120% · Render failed: …`), so long failure text cannot push it out
- Format lives in `MarkedCore` (`TextSize.label`) → unit-testable
- Coordinator keeps owning `textSize`; reports changes via closure, same pattern as `setFailure`

## Tasks

- [x] red: `TextSize.label` tests (nil at 100, `"120%"`, `"50%"`)
- [x] green: `TextSize.label`
- [x] wire: coordinator `textSize` didSet → `showTextSize` → `ReaderView` `@State` → subtitle
- [x] live check: subtitle shows `110%`, hides at Cmd-0
- [x] D51 in grill.md, README line
- [x] code-reviewer loop until clean
- [x] commit

## Unresolved

- none
