# Product Architecture

## Direction

The product code uses only the validated minimum path from the POC work.

The old validation code stays available for reference, but it is not imported by the product CLI or product core.

## Directory Layout

```text
Sources/
  NotionTabsCore/
    Models/
    State/
    AX/
    Services/

  notion-tabs/
    main.swift

  NotionTabsV2/
    validation/diagnostic implementation

  NotionTabsPOC/
    legacy initial POC
```

## Product Path

`NotionTabsCore` is the product engine.

- `NotionStateStore`: reads `state.json` as window/tab inventory.
- `WindowMenuReader`: reads Notion's Window menu.
- `FocusedWindowReader`: reads `AXFocusedWindow` as active truth.
- `TabStripReader`: finds preferred top tab-strip `AXButton` candidates.
- `CoordinateClicker`: brings Notion frontmost, raises the AX window, and clicks the tab button center.
- `NotionTabsService`: exposes `listWindows`, `focusWindow`, and `focusTab`.

`notion-tabs` is the product CLI.

```bash
swift run notion-tabs list
swift run notion-tabs focus-window --window 3
swift run notion-tabs focus-tab --window 2 --tab 4
```

## Explicitly Excluded From Product Core

- AX tree full dumps
- watch/sample loops
- role count and button-like dumps
- WebArea-only experiments
- point diagnostics
- JSONL run logger
- tab activation via `AXPress`
- tab activation via `AXScrollToVisible + AXPress`

These remain in `NotionTabsV2` only as diagnostic history/reference.

## Current Product Verification

- `swift build`: pass
- `swift run notion-tabs list`: pass
- `swift run notion-tabs focus-window --window 3`: pass
- `swift run notion-tabs focus-tab --window 2 --tab 4`: pass
- Final `swift run notion-tabs list` confirmed focused AX title as `Docs 작성/제작`.

## Product CLI Recheck

Issue found:

- `swift run notion-tabs focus-tab --window 2 --tab 1` initially failed with `tab click posted, but focus verification failed`.
- `notion-tabs-v2 focus-tab --window-id 2 --tab-id 1` succeeded for the same scenario.

Cause:

- Product Core was resolving the target window twice:
  - once inside `focusWindow`,
  - then again inside `focusTab` after window focus.
- Because `state.json` can change or lag, this was not identical to the validated v2 sequence.

Fix:

- `focusTab` now reads and resolves `targetWindow`/`targetTab` once.
- It then focuses that exact resolved `targetWindow`.
- The resolved target is kept through tab observation and coordinate click.

Recheck after fix:

- `swift run notion-tabs focus-tab --window 2 --tab 1`: pass
- `swift run notion-tabs focus-tab --window 1 --tab 2`: pass
- `swift run notion-tabs focus-tab --window 2 --tab 4`: pass
- `swift run notion-tabs focus-tab --window 3 --tab 1`: pass
- `swift run notion-tabs list`: pass, focused AX title `알로콘`.

## Important Product Assumptions

- `state.json` is inventory, not realtime active truth.
- `AXFocusedWindow` is immediate active truth.
- Window focus uses Notion Window menu.
- Tab focus uses coordinate click on a validated top tab-strip `AXButton`.
- Window/tab references accept either display index or id prefix.
