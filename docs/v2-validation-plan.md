# V2 Validation Plan

Updated: 2026-04-25

## Purpose

V2 should not be a smarter version of the current PoC.

V2 should be a validation harness that answers one question at a time:

- What exactly can be observed?
- What exactly can be matched?
- What exactly can be activated?
- When something fails, which assumption failed?

The goal is closed validation. Each step must produce a pass, fail, or blocked result with enough structured evidence to explain why.

## Core Principle

Do not combine discovery, matching, activation, and tab pressing in one command until each lower-level assumption has already passed.

The current PoC explored many possible paths. V2 should reduce the system to small, isolated experiments.

## Non-Goals

- No menubar UI.
- No hotkey UI.
- No product interaction polish.
- No automatic fallback chain until individual fallback methods are separately validated.
- No OCR or screenshot-based product path.
- No hidden mutation during source-reading commands.

## Validation Layers

V2 has three layers.

### Layer 1: Source

Question:

- Can this source observe the current Notion state?

Allowed actions:

- Read data only.
- No window activation.
- No tab activation.
- No focus changes.

Sources:

- Notion process via `NSRunningApplication`.
- Persisted Notion state via `state.json`.
- Live windows via ScreenCaptureKit.
- Live windows via Quartz Window Services.
- Live windows via AX.
- Window menu items via AX.
- Focused-window tabs via AX.

Output:

- Raw source records.
- Source freshness.
- Source confidence.
- No merged interpretation unless explicitly requested.

### Layer 2: Bridge

Question:

- Can a record from one source be proven to refer to the same real Notion window or tab as a record from another source?

Allowed actions:

- Read multiple sources.
- Compare title, frame, window ID, active title, tab ID, and source-specific metadata.
- No activation unless the bridge experiment explicitly says it is testing activation as the bridge.

Examples:

- persisted window -> ScreenCaptureKit window
- persisted window -> Quartz window
- persisted window -> Window menu item
- Window menu item -> focused AX window after selecting it
- persisted tab -> AX tab after target window is focused

Output:

- Matched, ambiguous, missing, or blocked.
- Evidence list.
- Match score and reason.

### Layer 3: Action

Question:

- If source and bridge already passed, can V2 perform exactly one action and confirm the expected state change?

Allowed actions:

- Activate app.
- Activate one window.
- Press one tab.
- Invoke one fallback method, but only in a command dedicated to that method.

Output:

- Pre-state.
- Action attempted.
- Post-state.
- Confirmation result.
- Timing.

## Fixed Assumptions

V2 should explicitly validate these assumptions in order.

### A0. Environment Ready

Assumption:

- Notion is running and Accessibility permission is available.

Validation:

- Find Notion process.
- Print PID, bundle ID, localized name, activation policy, frontmost/hidden status.
- Print Accessibility trusted status.

Pass:

- Notion process found.
- Accessibility trusted.

Fail:

- Notion not found.
- Accessibility not trusted.

Blocked:

- User has not opened Notion or granted permission.

### A1. Persisted State Is Parseable

Assumption:

- `state.json` can be parsed into windows and tabs.

Validation:

- Read state file.
- Print file path, modified time, age, byte size.
- Print window count and per-window tab count.
- Print window ID, active title, bounds, tab IDs, and tab titles.

Pass:

- File exists.
- Required fields parse.
- At least one window with at least one tab is present.

Fail:

- File exists but required fields are missing or malformed.

Blocked:

- File missing.

### A2. Persisted State Is Fresh Enough

Assumption:

- `state.json` updates soon enough after Notion state changes to be usable.

Validation:

- Run a watch command.
- User changes active tab, opens tab, closes tab, and opens/moves window.
- Command records detection latency for each change.

Pass:

- Each expected change appears within the configured threshold.

Fail:

- Change does not appear or appears with wrong data.

Blocked:

- User did not perform the requested manual action.

Initial threshold:

- 2 seconds for active-tab change.
- 5 seconds for window/tab open or close.

### A3. Live Window Sources Can See Current Windows

Assumption:

- ScreenCaptureKit and/or Quartz can see currently live Notion windows.

Validation:

- Read ScreenCaptureKit all-windows.
- Read ScreenCaptureKit onscreen-only.
- Read Quartz windows.
- Print window ID, title, frame, onscreen, active, layer, alpha.

Pass:

- At least one live Notion content window appears when Notion has an open window.

Fail:

- Notion has an open visible window but no source sees it.

Blocked:

- Notion has no open window.

### A4. Persisted Windows Match Live Windows

Assumption:

- Each persisted window can be matched to a live window with enough confidence.

Validation:

- Compare persisted windows against ScreenCaptureKit and Quartz.
- Match on title when available.
- Match on frame with tolerance.
- Report duplicates and ambiguous candidates.

Pass:

- Every persisted window has exactly one high-confidence live match.

Soft Pass:

- Current visible target window has exactly one high-confidence live match.

Fail:

- Persisted windows are stale, missing, duplicated, or ambiguous.

### A5. Window Menu Exposes Activatable Target Windows

Assumption:

- Notion's Window menu exposes real document windows that can be selected.

Validation:

- Read full Window menu.
- Classify each item as system command, separator, tab-navigation command, or document-window candidate.
- Compare document-window candidates against persisted titles and live titles.

Pass:

- Target document windows appear as menu candidates.

Fail:

- Menu has no document-window candidates while live windows exist.

Blocked:

- Notion is not running or AX menu cannot be read.

### A6. Window Menu Selection Focuses The Expected Window

Assumption:

- Pressing a target Window menu item focuses the expected Notion window.

Validation:

- Start from a chosen target window candidate.
- Record pre-state from persisted, live, menu, and AX focused window.
- Press exactly one Window menu item.
- Poll focused AX window until timeout.
- Compare focused title and frame with target evidence.

Pass:

- Focused AX window matches target title and frame.

Soft Pass:

- Focused AX window matches target title, but frame evidence is unavailable or unreliable.

Fail:

- Different window focused.
- No focused AX window appears.

### A7. Focused Window Exposes Tabs Through AX

Assumption:

- Once the target window is focused, AX exposes a usable tab strip.

Validation:

- Read focused AX window.
- Scan strict tab candidates.
- Scan raw tab candidates.
- Print role, title, value, frame, actions, selected state.

Pass:

- Strict scan returns non-empty tab list matching visible tab order.

Soft Pass:

- Raw scan returns useful candidates but strict scan needs tuning.

Fail:

- No tab candidates or obvious false positives only.

### A8. Persisted Target Tab Matches AX Tab

Assumption:

- A persisted tab can be matched to an AX tab after the window is focused.

Validation:

- Pick a persisted tab from the focused target window.
- Compare persisted title/index/tab ID with AX candidate title/index.
- Detect duplicate titles.

Pass:

- Exactly one AX candidate matches the persisted target title.

Fail:

- No candidate matches.
- Multiple candidates match.

### A9. AXPress Activates The Target Tab

Assumption:

- Pressing the matched AX tab activates it.

Validation:

- Record focused window title, selected tab index, and visible tab candidates.
- Run `AXScrollToVisible` only if explicitly enabled for this test.
- Run `AXPress`.
- Poll focused window title and selected state.

Pass:

- Focused window title or selected AX state confirms target tab.

Soft Pass:

- Title confirms target but selected AX state is unavailable.

Fail:

- Action succeeds at AX level but target tab does not become active.
- AX action itself fails.

## Manual State Matrix

V2 validation must be repeatable across these states.

### State 1: Single Visible Window

Setup:

- Open Notion desktop app.
- Open one Notion window.
- Open 3-5 tabs with distinct titles.

Purpose:

- Establish the simplest happy path.

Required assumptions:

- A0 through A9.

### State 2: Two Visible Windows In Same Space

Setup:

- Open two Notion windows in the same Space.
- Use distinct active page titles.
- Use at least 3 tabs per window.

Purpose:

- Validate multi-window matching without Spaces complexity.

Required assumptions:

- A0 through A9.
- Duplicate-window detection should be checked.

### State 3: Window In Inactive Space

Setup:

- Move one Notion window to another macOS Space.
- Keep current Space active.
- Do not manually switch to the target Space during source-reading tests.

Purpose:

- Validate cross-Space visibility and activation behavior.

Required assumptions:

- A0 through A9.
- Pay special attention to AX and ScreenCaptureKit differences.

### State 4: Minimized Window

Setup:

- Minimize one Notion window.
- Keep another app or Notion window visible.

Purpose:

- Validate whether live sources and Window menu can still bridge to minimized targets.

Required assumptions:

- A0 through A9.

### State 5: Long Tab Strip

Setup:

- Open one Notion window with at least 10 tabs.
- Pick visible, partially hidden, and overflow-position tabs.

Purpose:

- Validate tab candidate scanning and `AXScrollToVisible`.

Required assumptions:

- A7 through A9.

### State 6: Duplicate Titles

Setup:

- Open two tabs or windows with the same visible title.

Purpose:

- Confirm that V2 reports ambiguity instead of silently choosing the wrong target.

Required assumptions:

- A4, A5, A8.

Expected result:

- Ambiguous, not pass.

## Proposed V2 Commands

Commands should be boring and single-purpose.

### Environment

```bash
notion-tabs-v2 env
```

Validates A0.

Output:

- Process record.
- Permission record.
- Exit code `0` only when ready.

### Source Commands

```bash
notion-tabs-v2 source persisted
notion-tabs-v2 source persisted-watch --duration 30 --threshold-ms 2000
notion-tabs-v2 source live-windows
notion-tabs-v2 source ax-windows
notion-tabs-v2 source window-menu
notion-tabs-v2 source focused-tabs --strict
notion-tabs-v2 source focused-tabs --raw
```

Validates A1, A2, A3, A5, and A7.

Rules:

- Source commands must not activate windows.
- Source commands must not press tabs.
- Source commands must always print source name, timestamp, and raw counts.

### Bridge Commands

```bash
notion-tabs-v2 bridge windows
notion-tabs-v2 bridge menu
notion-tabs-v2 bridge focused-window --window-id <persisted-window-id>
notion-tabs-v2 bridge focused-tabs --window-id <persisted-window-id>
```

Validates A4, A5, A6, and A8.

Rules:

- Bridge commands must print all candidate matches.
- Bridge commands must report ambiguity explicitly.
- Bridge commands must not continue to activation when bridge fails.

### Action Commands

```bash
notion-tabs-v2 action focus-window --window-id <persisted-window-id> --strategy app-first
notion-tabs-v2 action focus-window --window-id <persisted-window-id> --strategy menu-only
notion-tabs-v2 action press-tab --window-id <persisted-window-id> --tab-id <persisted-tab-id> --method ax-press
notion-tabs-v2 action press-tab --window-id <persisted-window-id> --tab-id <persisted-tab-id> --method ax-scroll-then-press
```

Validates A6 and A9.

Rules:

- `press-tab` requires the target window to already be focused or must fail early.
- `press-tab` must not activate a window implicitly.
- Each command may test only one action method.

### Scenario Commands

Scenario commands are allowed only after source, bridge, and action commands are stable.

```bash
notion-tabs-v2 scenario single-visible
notion-tabs-v2 scenario two-visible
notion-tabs-v2 scenario inactive-space
notion-tabs-v2 scenario minimized
notion-tabs-v2 scenario long-tabs
notion-tabs-v2 scenario duplicate-titles
```

Rules:

- Scenario commands should run a checklist of lower-level commands.
- Scenario commands should not introduce new behavior.
- Scenario output should be a compact pass/fail table with links to detailed logs.

## Log Requirements

Every command must write a run log.

Default directory:

```text
logs/v2/YYYYMMDD-HHMMSS-command-name/
```

Required files:

- `summary.md`: human-readable result.
- `events.jsonl`: one event per line.
- `sources.json`: raw source records used in the run.
- `result.json`: final machine-readable verdict.

Optional files:

- `ax-tree.txt`: only for AX dump commands.
- `notes.md`: manual notes after a scenario.

## Event Schema

Each `events.jsonl` line should include:

```json
{
  "timestamp": "2026-04-25T01:30:00.000+09:00",
  "phase": "source|bridge|action|confirm",
  "step": "short-step-name",
  "status": "pass|soft_pass|fail|blocked|info",
  "elapsed_ms": 123,
  "message": "short human-readable explanation",
  "evidence": {}
}
```

## Result Schema

`result.json` should include:

```json
{
  "command": "bridge windows",
  "scenario": "two-visible",
  "started_at": "2026-04-25T01:30:00.000+09:00",
  "ended_at": "2026-04-25T01:30:01.250+09:00",
  "verdict": "pass|soft_pass|fail|blocked",
  "failed_assumption": "A4",
  "summary": "Persisted window 2 matched two live candidates; ambiguous.",
  "counts": {
    "persisted_windows": 2,
    "screen_capture_windows": 2,
    "quartz_windows": 2,
    "ax_windows": 1,
    "menu_candidates": 2
  }
}
```

## Exit Codes

- `0`: pass.
- `1`: fail.
- `2`: blocked by environment or missing manual setup.
- `3`: ambiguous result.
- `4`: internal error.

Soft pass should still exit `0`, but `result.json` must preserve `soft_pass`.

## Evidence Rules

V2 should never say only "not found" when a lookup fails.

Every failure should include:

- What was requested.
- Which source was searched.
- How many candidates existed.
- What the closest candidates were.
- Why each closest candidate did not match.

Example:

```text
FAIL A4 persisted window did not match live window
requested:
  windowID=...
  title=...
  frame=(x:16,y:41,w:1424,h:859)
candidates:
  sc[1] title=... frame=... score=120 reason=title-mismatch,frame-distance=120
  cg[1] title=<empty> frame=... score=24 reason=title-missing,frame-match
decision:
  ambiguous
```

## Implementation Shape

Keep V2 separate from the current PoC.

Recommended package layout:

```text
Sources/NotionTabsV2/
  main.swift
  CLI/
    CommandParser.swift
  Validation/
    Assumption.swift
    Verdict.swift
    RunLogger.swift
  Sources/
    ProcessSource.swift
    PersistedStateSource.swift
    ScreenCaptureWindowSource.swift
    QuartzWindowSource.swift
    AXWindowSource.swift
    WindowMenuSource.swift
    FocusedTabsSource.swift
  Bridge/
    WindowMatcher.swift
    MenuMatcher.swift
    TabMatcher.swift
  Action/
    AppActivator.swift
    WindowMenuFocuser.swift
    AXTabPresser.swift
  Models/
    Records.swift
```

Rules:

- Each source returns records, not decisions.
- Matchers produce decisions, not side effects.
- Actions mutate state, but must require validated target records.
- Logging is mandatory and injected into every command.

## Implementation Phases

Current implementation status:

- Phase 1 has been started in `Sources/NotionTabsV2`.
- The package now builds a separate executable: `notion-tabs-v2`.
- Implemented commands:
  - `env`
  - `source persisted`
  - `source persisted-watch`
  - `source live-windows`
  - `source ax-windows`
  - `source window-menu`
  - `source focused-tabs --strict`
  - `source focused-tabs --raw`
- Each implemented command writes:
  - `summary.md`
  - `events.jsonl`
  - `sources.json`
  - `result.json`
- Bridge and action commands are intentionally not implemented yet.
- Phase 2 has been started.
- Implemented bridge commands:
  - `bridge windows`
  - `bridge menu`
- `bridge windows` merges identical live window evidence from Quartz and ScreenCaptureKit before deciding ambiguity.
- Phase 3 has been started.
- Implemented action/bridge commands:
  - `action focus-window --window-id ID --strategy app-first|menu-only --timeout-ms N`
  - `bridge focused-window --window-id ID`
- Tab action commands are intentionally not implemented yet.
- Mutating action commands and state-reading bridge commands must be run sequentially, not in parallel.

### Phase 1: Read-Only Sources

Implement:

- `env`
- `source persisted`
- `source live-windows`
- `source ax-windows`
- `source window-menu`
- `source focused-tabs`

Exit criteria:

- Every source command writes logs.
- Every source command can be run repeatedly without changing Notion focus or tabs.

### Phase 2: Matching

Implement:

- `bridge windows`
- `bridge menu`
- duplicate and ambiguity reporting

Exit criteria:

- Matching failures explain why.
- Duplicate titles are explicitly detected.

### Phase 3: Focus Only

Implement:

- `action focus-window`
- `bridge focused-window`

Exit criteria:

- Window activation can be validated without tab activation.
- Visible, inactive-Space, and minimized windows are reported separately.

### Phase 4: Focused Tabs Only

Implement:

- `bridge focused-tabs`
- `action press-tab --method ax-press`
- `action press-tab --method ax-scroll-then-press`

Exit criteria:

- Tab activation can be validated only after the target window is already focused.
- Failure clearly separates AX exposure from AX action.

### Phase 5: Scenarios

Implement:

- scenario wrappers for the manual state matrix.

Exit criteria:

- Each scenario generates a compact summary and detailed logs.
- Scenario commands only orchestrate lower-level commands.

## First Validation Run

Start with the simplest state.

Manual setup:

1. Open Notion desktop app.
2. Open exactly one Notion window.
3. Open 3 tabs with distinct page titles.
4. Keep the Notion window visible.

Run:

```bash
notion-tabs-v2 env
notion-tabs-v2 source persisted
notion-tabs-v2 source live-windows
notion-tabs-v2 source ax-windows
notion-tabs-v2 source window-menu
notion-tabs-v2 bridge windows
notion-tabs-v2 bridge menu
notion-tabs-v2 source focused-tabs --strict
notion-tabs-v2 bridge focused-tabs --window-id <id>
notion-tabs-v2 action press-tab --window-id <id> --tab-id <id> --method ax-press
```

Do not test Spaces, minimized windows, long tab strips, or fallback methods until the single-visible-window run passes.

## Decision Rule

If an assumption fails, stop adding features.

The next task must be one of:

- improve the experiment evidence,
- refine the assumption,
- implement the smallest fix needed for that assumption,
- or declare that assumption false and change the product direction.
