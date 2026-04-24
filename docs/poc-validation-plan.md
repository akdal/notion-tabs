# PoC Validation Plan

## Goal

Validate one thing only:

- Can the PoC read the current Notion window list and the tab list for each window correctly?

## Current Finding

On this environment:

- `AXWindows` returns only the focused Notion window.
- Notion's `Window` menu still exposes the full set of open windows.
- When one Notion window is moved to a different macOS Space, `AXWindows` still reports only the window visible in the current Space, while the `Window` menu continues to list both windows.
- Quartz Window Services can still expose multiple large Notion window candidates across Spaces, even when `AXWindows` reports only one.

That means direct AX window enumeration is insufficient for full-window validation. The reliable validation path is:

1. Read candidate window entries from the `Window` menu.
2. Activate each entry.
3. Read the now-focused window's tab strip via Accessibility.
4. Repeat and compare for stability.

## Commands

Baseline checks:

```bash
swift run notion-tabs-poc status
swift run notion-tabs-poc list
swift run notion-tabs-poc window-sources
swift run notion-tabs-poc menu-tabs
```

Primary automated validation:

```bash
swift run notion-tabs-poc verify-list --repeats 2 --pause-ms 500
```

Deeper diagnostics:

```bash
swift run notion-tabs-poc probe --window 1
swift run notion-tabs-poc probe --window 1 --raw
swift run notion-tabs-poc dump --depth 7
```

## Pass Criteria

- `verify-list` finds at least one candidate window in the `Window` menu.
- Each candidate activates successfully.
- Each activated window yields a non-empty tab list.
- Repeated runs return the same window titles and tab titles in the same order.

## Failure Signals

- `AXWindows` and menu traversal disagree and menu traversal cannot recover missing windows.
- A window menu item activates but no focused window can be read.
- Tab order changes across repeated runs without a UI change.
- Different window menu items produce identical focused window + identical tab snapshots.

## Automation Strategy

Primary:

- Use live Notion + Accessibility permission.
- Run `verify-list` as the end-to-end regression check for window/tab reading.

Fallback:

- If live Notion is unavailable, keep using `dump` and `probe` to collect fixture candidates for later offline scanner tests.

## Human Help Only If Needed

Human input is only needed when:

- Notion is not running.
- Accessibility permission is not granted.
- The desired windows are not currently open in Notion.
