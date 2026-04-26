# Implementation Status Summary

Updated: 2026-04-25 01:24 KST

## Scope

This document summarizes the current implementation state of the Notion tabs PoC and the main assumptions or weak points in the logic.

The project is still a PoC CLI, not a production menubar app. Its goal is to validate whether external macOS code can discover Notion windows/tabs and activate a selected tab.

## Current Project State

- The project is a Swift Package executable named `notion-tabs-poc`.
- The repo directory is not currently a Git repository, so branch, commit, and dirty-worktree state are unavailable.
- `swift build` succeeds.
- There is no automated test suite or CI configuration in the project.
- Validation is currently done through CLI commands and manually documented scenarios.
- Main implementation lives in `Sources/NotionTabsPOC/main.swift`.
- Supporting code is split into `Core`, `Accessibility`, and `Notion` folders.

## Command Surface

Implemented CLI commands include:

- `status`: checks Accessibility permission and whether Notion is running.
- `list`: reads Notion windows through Accessibility and scans tab candidates from exposed windows.
- `persisted-list`: reads Notion's local persisted `state.json`.
- `persisted-watch`: polls `state.json` and prints changed snapshots.
- `dump`: dumps the Notion Accessibility tree.
- `activate`: activates a window/tab using AX-discovered windows.
- `activate-window-persisted`: activates a window selected from persisted state.
- `activate-persisted`: activates a window and tab selected from persisted state.
- `repeat-activate-persisted`: repeats persisted activation for reliability checks.
- `activate-target`: activates by explicit window title and tab title.
- `probe`, `verify`, `verify-list`: diagnostic commands for AX candidate and activation behavior.
- `window-sources`, `window-map`, `menu-tabs`, `inspect-focused-window`, `inspect-window-menu`: source comparison and inspection commands.

## Discovery Flow

The implementation currently has several discovery paths:

- Process discovery uses `NSRunningApplication` through known Notion bundle IDs.
- AX window discovery reads `AXWindows`, `AXFocusedWindow`, and fallback descendants.
- AX tab discovery scans button-like elements near the top of an exposed Notion window.
- Window menu discovery reads the Notion `Window` menu via Accessibility.
- Quartz Window Services lists Notion window-server surfaces by PID.
- ScreenCaptureKit lists shareable Notion windows by bundle identifier.
- Persisted state reads `~/Library/Application Support/Notion/state.json`.

The strongest passive tab source is currently `state.json`, because it can contain all windows and all tabs even when AX does not expose every window.

## Activation Flow

The active product candidate is `app-first`:

1. Resolve target window/tab from persisted state or explicit titles.
2. Call `NSRunningApplication.activate(options: [.activateAllWindows])`.
3. Find the target in Notion's `Window` menu by title.
4. Press or pick the menu item.
5. Wait for the focused AX window title to match.
6. Scan the focused window's tab strip through AX.
7. Run `AXScrollToVisible` when available.
8. Run `AXPress` or `AXPick` on the target tab.
9. Confirm success by focused window title or AX selected-tab state.

`menu-only` remains as a baseline strategy, but the docs already treat `app-first` as the leading candidate for visible, minimized, and inactive-Space cases.

## Current Runtime Observation

During the latest local check:

- Build succeeded.
- Accessibility permission was available.
- `persisted-list` returned a stored snapshot with 4 windows and 26 total tabs.
- `list` did not return AX windows in that moment.

Important correction:

- The missing `list` output should be interpreted with the current machine state in mind.
- The user clarified that Notion was not actually running at that point.
- Therefore, the latest `list` failure is not evidence by itself that AX discovery is broken.
- It still remains true that the PoC has known AX exposure limitations across Spaces and app/window states, as recorded in the existing discovery documents.

## What Is Implemented Well Enough For PoC

- The code can locate a running Notion app by bundle ID.
- The code can request and check Accessibility permission.
- The code can dump AX structure for inspection.
- The code can parse Notion's persisted window/tab state.
- The code can compare multiple window sources.
- The code has separate commands for diagnostics, activation, and repeated validation.
- The current architecture recognizes that no single macOS API is sufficient for full discovery.

## Key Assumptions

- Notion's `state.json` format remains stable enough to parse.
- `state.json` is fresh enough for product use or can be validated before use.
- Persisted window and tab indices remain meaningful between list and activate operations.
- Window titles are sufficient to bridge persisted state, Window menu items, and AX focused windows.
- Active Notion window title usually matches the active tab title.
- AX exposes the focused Notion tab strip after the target window is activated.
- `AXScrollToVisible` followed by `AXPress` is enough for most tab switches.
- Duplicate window titles and duplicate tab titles are rare or can be tolerated for PoC validation.

## Main Risks And Suspect Logic

### 1. Persisted State Freshness

`state.json` is the strongest passive source, but it is an internal Notion file and appears eventually consistent.

Risk:

- A stale snapshot can show windows or tabs that are no longer live.
- A user may select an index from old state.
- Activation may target the wrong window or fail for reasons that look like AX/menu failure.

Needed:

- Add freshness checks using modification time.
- Cross-check persisted windows against live ScreenCaptureKit or Quartz candidates.
- Mark stale or unmatched persisted entries instead of treating them as fully valid.

### 2. Title-Based Identity

The implementation mostly matches windows and tabs by exact title.

Risk:

- Duplicate Notion page titles can select the wrong target.
- Window title, tab title, menu title, and persisted title can drift.
- Renames during activation can break confirmation.

Needed:

- Prefer stable IDs where available on the persisted side.
- Use title plus frame plus live source matching for windows.
- Detect duplicate titles and report ambiguity instead of silently choosing the first match.

### 3. Window Menu Candidate Filtering

The current menu candidate logic walks backward through the Window menu and treats the last non-empty block as document windows.

Risk:

- System menu items such as `Bring All to Front` or `Arrange in Front` can be mistaken for window candidates.
- The menu layout can vary by macOS version, Notion version, Stage Manager, tabs, or fullscreen state.

Needed:

- Filter out known system Window menu commands.
- Prefer matching candidates against persisted titles and live window-source titles.
- Report when the menu has no document-window candidates.

### 4. Documentation And Code Drift

Some docs say there is a coordinate-click fallback when AX does not confirm tab activation.

Current code:

- Implements `AXScrollToVisible`.
- Implements `AXPress` / `AXPick`.
- Does not appear to implement `CGEvent` coordinate-click fallback.
- Does not appear to implement `Cmd+1...9` or `Show Previous/Next Tab` fallback logic.

Risk:

- Validation notes overstate current implementation.
- Debugging may assume fallback behavior that is not actually present.

Needed:

- Either implement the documented fallback paths or update docs to mark them as planned.

### 5. AX Tab Heuristics

`NotionTabScanner` identifies tabs as button-like elements near the top of the window.

Risk:

- It can miss tabs when layout changes, tabs overflow, the window is narrow, or overlays are present.
- It can include non-tab buttons if they match the geometry/action heuristic.
- Selection state may be unavailable or unreliable.

Needed:

- Keep `probe` and `verify` outputs as primary tuning tools.
- Record false positives and false negatives from real sessions.
- Treat empty AX tab lists as an explicit unsupported/live-state condition.

### 6. Activation Confirmation

Success is confirmed mainly by focused window title matching the target tab title or by AX selected state.

Risk:

- Notion title updates can lag behind tab activation.
- A title match can be insufficient when duplicate titles exist.
- A tab can be active while AX selected state is missing.

Needed:

- Separate window activation confirmation from tab activation confirmation.
- Log focused title, selected index, target index, and available tabs consistently.
- Consider a confidence score instead of a single boolean.

### 7. Process Discovery Narrowness

The docs mention bundle ID and fallback name matching, but implementation currently uses known bundle IDs only.

Risk:

- A differently packaged Notion build may not be found.

Needed:

- Add a controlled fallback by localized name or executable name.
- Keep bundle ID as the preferred path.

### 8. Crash Safety In AX Wrapping

`AXElement` uses forced casts for some AX values.

Risk:

- Unexpected AX value types can crash the CLI during diagnostics.

Needed:

- Replace forced casts with guarded type checks.
- Return nil on unexpected AX values.

## Current Product Direction

The current best candidate remains hybrid:

- Use `NSRunningApplication` for process identity.
- Use `state.json` for passive full window/tab discovery, but only with freshness and live-source checks.
- Use ScreenCaptureKit or Quartz to validate live window existence and bounds.
- Use Window menu as an activation bridge.
- Use AX only after the target window is exposed, mainly for tab scanning and tab activation.
- Keep `app-first` as the default activation strategy unless further validation shows a better path.

## Recommended Next Work

1. Fix source validity before UI work.
2. Add stale persisted-state detection.
3. Cross-check persisted windows with ScreenCaptureKit or Quartz.
4. Harden Window menu candidate filtering.
5. Reconcile docs with actual fallback implementation.
6. Add ambiguity handling for duplicate titles.
7. Add safer AX value handling.
8. Re-run validation with Notion actually running and with fresh `persisted-list` output before each activation attempt.

