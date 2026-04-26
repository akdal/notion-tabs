# V2 Validation Results

Updated: 2026-04-25 01:51 KST

## Purpose

This document records closed validation results for the current `notion-tabs-v2` harness.

The purpose is not to prove the product works yet. The purpose is to prove whether the harness can isolate source, bridge, and action assumptions without hiding failures.

## Current Manual Setup

- Notion desktop app is running.
- Accessibility permission is trusted.
- Persisted state reports 4 Notion windows and 26 tabs.
- Live window sources report 4 total Notion windows.
- AX currently exposes 1 Notion window.
- The focused window during source validation was `@Last Monday VS Daily Stand-up`.

## Phase 1: Source Validation

### A0 Environment Ready

Command:

```bash
swift run notion-tabs-v2 env
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015050-env-50c366ec`
- Evidence:
  - Notion process found.
  - Accessibility trusted.

### A1 Persisted State Is Parseable

Command:

```bash
swift run notion-tabs-v2 source persisted
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015056-source-persisted-bd462439`
- Evidence:
  - `state.json` parsed.
  - windowCount=4
  - tabCount=26
  - ageSeconds=113.36

Notes:

- A1 is closed as pass.
- A2 freshness is not closed by this command.
- The age value proves the harness exposes freshness instead of hiding it.

### A3 Live Window Sources Can See Current Windows

Command:

```bash
swift run notion-tabs-v2 source live-windows
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015100-source-live-windows-b88188b0`
- Evidence:
  - Quartz windows: 4
  - ScreenCaptureKit all windows: 4
  - ScreenCaptureKit onscreen windows: 1

Interpretation:

- Live source discovery works for the current multi-window state.
- ScreenCaptureKit distinguishes visible/active from non-onscreen windows.

### AX Window Source

Command:

```bash
swift run notion-tabs-v2 source ax-windows
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015105-source-ax-windows-2035116e`
- Evidence:
  - AX windows: 1
  - AX focused/live title: `@Last Monday VS Daily Stand-up`

Interpretation:

- AX can read the current exposed window.
- AX does not currently expose all 4 live windows.
- This confirms the harness must not treat AX as the full window source.

### A5 Window Menu Source

Command:

```bash
swift run notion-tabs-v2 source window-menu
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015108-source-window-menu-6816d891`
- Evidence:
  - menuItems=22
  - documentCandidates=4
  - document candidates match the 4 persisted active titles.

### A7 Focused Tabs Source

Strict command:

```bash
swift run notion-tabs-v2 source focused-tabs --strict
```

Strict result:

- Verdict: pass
- Log: `logs/v2/20260425-015113-source-focused-tabs-strict-d5db9417`
- Evidence:
  - strict tabs=5
  - titles match the focused window's 5 visible tabs.

Raw command:

```bash
swift run notion-tabs-v2 source focused-tabs --raw
```

Raw result:

- Verdict: pass
- Log: `logs/v2/20260425-015116-source-focused-tabs-raw-f209b78d`
- Evidence:
  - raw tabs=6
  - raw scan includes `Edited Apr 13`, which appears to be a non-tab false positive.

Interpretation:

- Strict scanning is currently better for this focused window.
- Raw scanning is useful for diagnostics but must not be trusted as product tab list without filtering.

## Phase 2: Bridge Validation

### A4 Persisted Windows Match Live Windows

Command:

```bash
swift run notion-tabs-v2 bridge windows
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015120-bridge-windows-0648caca`
- Evidence:
  - matched=4
  - missing=0
  - ambiguous=0

Notes:

- The matcher merges identical Quartz and ScreenCaptureKit records into one evidence group.
- This avoids a false ambiguity when two source APIs report the same physical window.
- Some windows share the same frame, so title evidence is currently important.

### A5 Persisted Windows Match Window Menu

Command:

```bash
swift run notion-tabs-v2 bridge menu
```

Result:

- Verdict: pass
- Log: `logs/v2/20260425-015120-bridge-menu-fb7184c0`
- Evidence:
  - matched=4
  - missing=0
  - ambiguous=0

Interpretation:

- In the current state, Notion's Window menu provides an exact title bridge for all 4 persisted windows.

## Phase 3: Focus-Window Action Validation

### A6 Focus Already-Focused Window

Action command:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1000
```

Action result:

- Verdict: pass
- Log: `logs/v2/20260425-015126-action-focus-window-a6096d12`
- Evidence:
  - target=`@Last Monday VS Daily Stand-up`
  - action=`AXPress`
  - elapsedMS=83
  - preFocused and postFocused match target.

Bridge confirmation:

```bash
swift run notion-tabs-v2 bridge focused-window --window-id 20dfcda0
```

Bridge result:

- Verdict: pass
- Log: `logs/v2/20260425-015130-bridge-focused-window-7b755e80`
- Evidence:
  - focused title exact
  - frameDistance=0

### A6 Focus Different Visible/Live Window

Action command:

```bash
swift run notion-tabs-v2 action focus-window --window-id 98c52245 --strategy app-first --timeout-ms 1000
```

Action result:

- Verdict: pass
- Log: `logs/v2/20260425-015135-action-focus-window-264488e5`
- Evidence:
  - target=`Leaderboard + Gamification`
  - action=`AXPress`
  - elapsedMS=58
  - preFocused=`@Last Monday VS Daily Stand-up`
  - postFocused=`Leaderboard + Gamification`

Bridge confirmation:

```bash
swift run notion-tabs-v2 bridge focused-window --window-id 98c52245
```

Bridge result:

- Verdict: pass
- Log: `logs/v2/20260425-015140-bridge-focused-window-2d42dbea`
- Evidence:
  - focused title exact
  - frameDistance=0

## Closed Results

- A0 environment ready: pass
- A1 persisted parse: pass
- A3 live window source: pass for current state
- A4 persisted-to-live window bridge: pass for current state
- A5 persisted-to-menu bridge: pass for current state
- A6 focus-window action: pass for two current targets
- A7 focused-tabs source: pass for current focused window, with strict mode preferred

## Not Closed Yet

- A2 persisted freshness is not closed.
- Inactive Space focus behavior is not closed in this validation run.
- Minimized window behavior is not closed in this validation run.
- Duplicate title handling is not closed in this validation run.
- Long tab strip behavior is not closed in this validation run.
- A8 persisted target tab to AX tab matching is implemented and partially validated.
- A9 tab activation is not implemented.

## Important Observations

- AX exposes only 1 window while live sources expose 4 windows.
- Window menu exposes 4 document candidates.
- ScreenCaptureKit all-windows and Quartz both see all 4 windows in this state.
- ScreenCaptureKit onscreen-only sees only 1 window.
- Raw focused-tab scan produced a likely false positive: `Edited Apr 13`.
- Some windows share identical frames, so matching by frame alone is insufficient.
- The current successful bridge depends on exact titles being available and distinct.

## Freshness Attempt

### A2 Persisted State Freshness

Smoke command:

```bash
swift run notion-tabs-v2 source persisted-watch --duration 3 --threshold-ms 2000
```

Smoke result:

- Verdict: pass for command mechanics only
- Log: `logs/v2/20260425-015455-source-persisted-watch-78bd9110`
- Evidence:
  - initial snapshot observed
  - windows=4
  - tabs=26

Manual active-tab watch command:

```bash
swift run notion-tabs-v2 source persisted-watch --duration 30 --threshold-ms 2000
```

Manual active-tab watch result:

- Verdict: not closed
- Log: `logs/v2/20260425-015510-source-persisted-watch-0ade81f3`
- Evidence:
  - initial snapshot observed
  - no additional snapshot changes observed during the 30 second window

Interpretation:

- This does not prove A2 false.
- It also does not prove A2 true.
- Possible explanations:
  - no manual Notion state change occurred during the watch window,
  - Notion did not persist the active-tab change during the watch window,
  - the watched signature did not include the changed field.
- The signature now includes window ID, active title, bounds, tab IDs, and tab titles.
- A2 needs a deliberate manual test with a confirmed user action.

Second manual active-tab watch setup:

1. Focus window `20dfcda0`.
2. Start a 45 second watch.
3. User manually clicked the `운영` tab.
4. User waited briefly.
5. User clicked back to `@Last Monday VS Daily Stand-up`.

Focus command:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1000
```

Focus result:

- Verdict: pass
- Log: `logs/v2/20260425-015847-action-focus-window-231f3639`

Watch command:

```bash
swift run notion-tabs-v2 source persisted-watch --duration 45 --threshold-ms 2000
```

Watch result:

- Verdict: fail for active-tab freshness threshold
- Log: `logs/v2/20260425-015852-source-persisted-watch-a97eea84`
- Evidence:
  - user confirmed the tab-switch action happened during the watch window
  - watch observed only the initial snapshot
  - no signature change was observed for active title, bounds, tab IDs, or tab titles

Post-watch persisted read:

```bash
swift run notion-tabs-v2 source persisted
```

Post-watch result:

- Log: `logs/v2/20260425-015943-source-persisted-09e01e1b`
- Evidence:
  - `state.json` modifiedAt was recent
  - Window `20dfcda0` active title was still `@Last Monday VS Daily Stand-up`
  - The intermediate active tab `운영` was not observed in persisted state

Current A2 conclusion:

- The broad statement "`state.json` is parseable and eventually updated" remains true enough for A1.
- The specific product-critical assumption "active-tab changes are reflected in `state.json` within 2 seconds" failed this test.
- `state.json` should not be treated as a reliable live active-tab source.
- For live active-tab state after focusing a window, AX should be validated separately instead of trusting persisted state.

### A2/A7 Combined Sampling

Purpose:

- Compare `state.json` and AX focused-window state on the same timeline.
- Poll both sources every 2 seconds for 15 samples.

Command:

```bash
swift run notion-tabs-v2 source sample-state --samples 15 --interval-ms 2000
```

Result:

- Verdict: pass for sampler mechanics
- Log: `logs/v2/20260425-020235-source-sample-state-fad86d19`
- Summary:
  - samples=15
  - persistedTransitions=1
  - axTransitions=6

Observed timeline:

- Samples 1-3:
  - AX focused title: `@Last Monday VS Daily Stand-up`
  - persisted active title for window `20dfcda0`: `@Last Monday VS Daily Stand-up`
- Samples 4-6:
  - AX focused title: `Phase 1 런칭 QA list`
  - persisted active title for window `20dfcda0`: still `@Last Monday VS Daily Stand-up`
- Samples 7-9:
  - AX focused title: `운영`
  - persisted active title for window `20dfcda0`: still `@Last Monday VS Daily Stand-up`
- Samples 10-11:
  - AX focused title: `Versus 수집 이벤트`
  - AX strict tabs increased to 6
  - persisted active title for window `20dfcda0`: still `@Last Monday VS Daily Stand-up`
- Sample 12:
  - AX focused title: `Phase 1 런칭 QA list`
  - persisted active title for window `20dfcda0`: still `@Last Monday VS Daily Stand-up`
- Samples 13-14:
  - AX focused title: `@Last Monday VS Daily Stand-up`
  - persisted active title for window `20dfcda0`: still `@Last Monday VS Daily Stand-up`
- Sample 15:
  - AX focused title: `Leaderboard + Gamification`
  - AX strict tabs increased to 7
  - persisted active title for window `20dfcda0`: finally changed to `Leaderboard + Gamification`

Interpretation:

- AX reflected focused tab/window-title changes immediately enough for 2 second polling.
- `state.json` did not reflect most intermediate active-tab changes.
- `state.json` eventually changed once near the end, but not with complete intermediate history.
- `state.json` cannot be used as a complete real-time event stream.
- `state.json` can still be useful as a window/tab candidate snapshot.
- Live active tab should come from AX after focusing the target window.

## Decision

Do not implement tab activation yet.

Before tab action work, validate the existing harness across at least:

- one intentionally fresh persisted-state watch run,
- one inactive-Space setup,
- one minimized-window setup,
- one duplicate-title setup.

## Phase 4: Focused Tabs Bridge

### A8 Focused Tabs Bridge: Window `20dfcda0`

Setup:

1. Focus window `20dfcda0`.
2. Run focused-tabs bridge for the same window.

Focus command:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1000
```

Focus result:

- Verdict: pass
- Log: `logs/v2/20260425-021649-action-focus-window-7c1e93ac`
- Evidence:
  - focused window became `Leaderboard + Gamification`

Bridge command:

```bash
swift run notion-tabs-v2 bridge focused-tabs --window-id 20dfcda0
```

Bridge result:

- Verdict: pass
- Log: `logs/v2/20260425-021654-bridge-focused-tabs-bb2188c1`
- Evidence:
  - persisted tabs=7
  - AX strict tabs=7
  - matched=7
  - missing=0
  - ambiguous=0

Interpretation:

- A8 passes for this focused window.
- Persisted tab title/index and AX strict tab title/index align exactly in this state.

### A8 Focused Tabs Bridge: Window `bb1a6a8e`

Setup:

1. Focus window `bb1a6a8e`.
2. Run focused-tabs bridge for the same window.

Focus command:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1000
```

Focus result:

- Verdict: pass
- Log: `logs/v2/20260425-021702-action-focus-window-cb6fb740`
- Evidence:
  - focused window became `Versus Liquidity Provider (VLP)`

Bridge command:

```bash
swift run notion-tabs-v2 bridge focused-tabs --window-id bb1a6a8e
```

Bridge result:

- Verdict: fail
- Log: `logs/v2/20260425-021709-bridge-focused-tabs-e0623469`
- Evidence:
  - focused window bridge passed
  - persisted tabs=4
  - AX strict tabs matched=0
  - all persisted tabs were missing from AX focused tabs

Follow-up source checks:

```bash
swift run notion-tabs-v2 source focused-tabs --strict
swift run notion-tabs-v2 source focused-tabs --raw
```

Follow-up results:

- Strict log: `logs/v2/20260425-021714-source-focused-tabs-strict-cc0a2249`
- Raw log: `logs/v2/20260425-021719-source-focused-tabs-raw-0f738f8d`
- Evidence:
  - strict tabs=0
  - raw tabs=0

Interpretation:

- This is not a title/index matcher failure.
- AX did not expose any tab candidates for this focused window.
- A8 is not globally valid across all focused Notion windows in the current state.
- Tab activation must not be implemented as if AX tabs are always available after focusing a window.

Current A8 conclusion:

- A8 passes for at least one focused Notion window through button-like AX tab candidates.
- A8 did not pass for `bb1a6a8e` through the button-like scanner.
- The later AX tree check shows this is not because AX has no tab/page title data.
- The correct conclusion is that AX exposes different shapes depending on the focused window/state:
  - button-like `AXButton` tab candidates in some states,
  - titled `AXWebArea` page candidates in other states.
- The next work should validate a combined title-observation source before implementing A9 tab activation.

### A8 Recheck: Window `bb1a6a8e`

Reason:

- User noted that mouse movement during the previous run may have affected the result.
- The same target was tested again with sequential commands.

Focus command:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1000
```

Focus result:

- Verdict: pass
- Log: `logs/v2/20260425-021839-action-focus-window-a3ba2e41`

Focused-window bridge:

```bash
swift run notion-tabs-v2 bridge focused-window --window-id bb1a6a8e
```

Focused-window result:

- Verdict: pass
- Log: `logs/v2/20260425-021843-bridge-focused-window-686be5ff`
- Evidence:
  - focused title=`Versus Liquidity Provider (VLP)`
  - frameDistance=0

Focused-tabs source checks:

```bash
swift run notion-tabs-v2 source focused-tabs --strict
swift run notion-tabs-v2 source focused-tabs --raw
```

Focused-tabs results:

- Strict log: `logs/v2/20260425-021847-source-focused-tabs-strict-2821f43d`
- Raw log: `logs/v2/20260425-021851-source-focused-tabs-raw-f58f785e`
- Evidence:
  - strict tabs=0
  - raw tabs=0

Focused-tabs bridge:

```bash
swift run notion-tabs-v2 bridge focused-tabs --window-id bb1a6a8e
```

Bridge result:

- Verdict: fail
- Log: `logs/v2/20260425-021854-bridge-focused-tabs-6748c861`
- Evidence:
  - focused window still matched
  - all persisted tabs were missing from AX focused tabs

Recheck interpretation:

- The failure reproduced after a clean sequential run.
- The issue is unlikely to be caused only by mouse movement during the previous test.
- For this focused window, the current button-like AX tab scanner sees no candidates.
- This does not mean AX has no page/tab title data.

### A8 AX Tree Investigation

Reason:

- `bb1a6a8e` focused-window bridge passed, but strict/raw button-like tab scans returned 0.
- Need to separate "AX has no tab data" from "the current scanner looks for the wrong AX shape".

Command:

```bash
swift run notion-tabs-v2 source focused-ax-tree --depth 10
```

Result:

- Verdict: pass for dump mechanics
- Log: `logs/v2/20260425-022225-source-focused-ax-tree-7ea66a68`
- AX tree file: `logs/v2/20260425-022225-source-focused-ax-tree-7ea66a68/ax-tree.txt`
- Evidence:
  - focused title=`Versus Liquidity Provider (VLP)`
  - roleCounts:
    - AXButton=3
    - AXGroup=35
    - AXStaticText=1
    - AXWebArea=5
    - AXWindow=1
  - buttonLike=3
  - the 3 button-like elements are only macOS window control buttons

Key AX tree observation:

- The tab area appears as `AXWebArea title='Tab Bar'`.
- Other tab/page titles appear as titled `AXWebArea` elements:
  - `Privy 다중 계정 연동 기획`
  - `Docs 작성/제작`
  - `Alpha 포인트 리더보드`
  - `Versus Liquidity Provider (VLP)`
- These are not exposed as `AXButton` in this state.

Interpretation:

- AX does expose tab/page title data for this window.
- The current button-based tab scanner is too narrow for this state.
- However, WebArea exposure is not yet proven to preserve tab order or actionability.

### A8 WebArea Candidate Source

New command:

```bash
swift run notion-tabs-v2 source focused-tab-webareas
```

Window `bb1a6a8e` result:

- Log: `logs/v2/20260425-022325-source-focused-tab-webareas-80a88063`
- Evidence:
  - titled AXWebAreas=5
  - includes 4 persisted tab titles
  - also includes non-tab `Tab Bar`
  - order differs from persisted tab order

Window `20dfcda0` result:

- Log: `logs/v2/20260425-022337-source-focused-tab-webareas-d635d1de`
- Evidence:
  - titled AXWebAreas=8
  - includes 7 persisted tab titles
  - also includes non-tab `Tab Bar`
  - order differs from persisted tab order

Current WebArea conclusion:

- WebArea candidates can recover tab titles in states where button-like tab scanning returns 0.
- WebArea candidates are useful evidence for title presence.
- WebArea candidates are not yet valid as an order source.
- WebArea candidates are not yet valid as an activation source.
- A8 should be split:
  - A8a: focused tab titles are observable through some AX source
  - A8b: focused tab order is reconstructable
  - A8c: focused tab candidate is actionable

Correction from sample-state recheck:

- The earlier `sample-state` run did show AX focused title and AX strict button tabs at 2 second intervals.
- That run mostly observed window `20dfcda0`, where the tab strip was exposed as button-like `AXButton` candidates.
- It did not prove that every focused Notion window exposes tabs through the same AX shape.
- The current evidence now says:
  - `20dfcda0`: button-like AX tab source works.
  - `bb1a6a8e`: button-like AX tab source fails, but titled `AXWebArea` source recovers page/tab titles.
- Therefore A8 should not be treated as failed globally.
- A8 should be refined into separate title-observation, order, and actionability assumptions.

Logging note:

- While reviewing `sample-state`, some numeric values such as index `1` were serialized as `true` in `sources.json`/`events.jsonl`.
- This was a JSON conversion bug in the validation harness, not a Notion/AX behavior.
- The encoder was corrected after this review so numeric evidence remains numeric in future logs.

### A8 Recheck: Is AX Shape Window-Dependent?

Reason:

- The earlier conclusion said "AX exposes different shapes depending on the focused window/state".
- User asked to verify whether this conclusion is actually supported by evidence.

Current setup:

- Persisted state reports 2 windows.
- Both windows currently have the same frame:
  - `20dfcda0`: `(x:8,y:34,w:709,h:859)`
  - `bb1a6a8e`: `(x:8,y:34,w:709,h:859)`

Window `20dfcda0` commands:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1000
swift run notion-tabs-v2 source focused-tabs --strict
swift run notion-tabs-v2 source focused-tabs --raw
swift run notion-tabs-v2 source focused-tab-webareas
swift run notion-tabs-v2 source focused-ax-tree --depth 10
```

Window `20dfcda0` results:

- Focus log: `logs/v2/20260425-022825-action-focus-window-547c5639`
- Strict log: `logs/v2/20260425-022830-source-focused-tabs-strict-2df6b7b0`
- Raw log: `logs/v2/20260425-022835-source-focused-tabs-raw-37356d20`
- WebArea log: `logs/v2/20260425-022839-source-focused-tab-webareas-4aaaffd6`
- AX tree log: `logs/v2/20260425-022843-source-focused-ax-tree-2df0995e`
- Evidence:
  - strict button-like tabs=0
  - raw button-like tabs=0
  - titled WebAreas=8
  - AXButton count=3, all appear to be macOS window controls
  - AXWebArea count=8

Window `bb1a6a8e` commands:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1000
swift run notion-tabs-v2 source focused-tabs --strict
swift run notion-tabs-v2 source focused-tabs --raw
swift run notion-tabs-v2 source focused-tab-webareas
swift run notion-tabs-v2 source focused-ax-tree --depth 10
```

Window `bb1a6a8e` results:

- Focus log: `logs/v2/20260425-022851-action-focus-window-1d61a538`
- Strict log: `logs/v2/20260425-022856-source-focused-tabs-strict-dab489a4`
- Raw log: `logs/v2/20260425-022903-source-focused-tabs-raw-40a1ff4b`
- WebArea log: `logs/v2/20260425-022907-source-focused-tab-webareas-85b491bc`
- AX tree log: `logs/v2/20260425-022913-source-focused-ax-tree-3ee441ff`
- Evidence:
  - strict button-like tabs=0
  - raw button-like tabs=0
  - titled WebAreas=5
  - AXButton count=3, all appear to be macOS window controls
  - AXWebArea count=5

Corrected interpretation:

- The statement "AX shape differs by window" is not supported by this recheck.
- In the current setup, both windows expose tab/page titles through titled `AXWebArea` elements, not button-like `AXButton` tab elements.
- The earlier `sample-state` run did show button-like `AXButton` tabs, so the AX shape can change across Notion state/layout/session.
- The stronger, better-supported conclusion is:
  - AX tab exposure is state/layout/session-dependent.
  - It is not enough to hard-code one AX shape.
  - Current narrow window layout appears to expose tab/page title data as `AXWebArea`.
  - A wider earlier layout exposed visible tab strip entries as `AXButton`.

### AX Focused Window CLI

Reason:

- User asked to expose the original AX focused-window check as a direct CLI command.
- This command intentionally does not read `state.json`; it reads Notion's `AXFocusedWindow` directly.

Command:

```bash
swift run notion-tabs-v2 source focused-window
```

Observed result:

- Log: `logs/v2/20260425-023225-source-focused-window-44fb2e35`
- AX focused-window title: `Alpha 포인트 리더보드`
- AX role: `AXWindow`
- AX frame: `(x:8,y:34,w:709,h:859)`
- `AXFocused`: `false`
- `AXMain`: `true`
- actions: `[AXRaise]`

Cross-check:

- `swift run notion-tabs-v2 source persisted`
- Log: `logs/v2/20260425-023232-source-persisted-0ab9b1db`
- `state.json` also reported Window 2 active tab as `Alpha 포인트 리더보드`.

Interpretation:

- `source persisted` is a parsed view of `~/Library/Application Support/Notion/state.json`, not AX.
- `source focused-window` is direct AX evidence from `AXFocusedWindow`.
- In this run, direct AX focused-window title matched the active title in persisted state.
- The child window's `AXFocused=false` should not be treated as the primary active-window signal; the returned `AXFocusedWindow` object plus title/frame is the stronger signal.

### Focus Diagnostics: Minimized and Other Spaces

Reason:

- User observed that `AXFocusedWindow` can return a Notion window even when Notion is not foregrounded or the window is on another Space.
- User also observed that when all Notion windows are minimized, `AXFocusedWindow` can return nothing.
- This means `AXFocusedWindow` must not be treated as the complete window inventory or as guaranteed visibility evidence.

New command:

```bash
swift run notion-tabs-v2 source focus-diagnostics
```

What it reads:

- Parsed persisted state from `state.json`
- Direct `AXFocusedWindow`
- Direct AX windows via `AXWindows`
- Window menu document candidates
- Quartz live windows
- ScreenCaptureKit all windows

Observed result:

- Log: `logs/v2/20260425-023947-source-focus-diagnostics-8e53f9d0`
- `state.json`: 2 windows
- `AXFocusedWindow`: `운영`
- `AXWindows`: 2 windows
  - `Privy 다중 계정 연동 기획`, `minimized=true`
  - `운영`, `minimized=false`, `main=true`
- Window menu document candidates: 2
- Quartz windows: 3, including both titled Notion windows
- ScreenCaptureKit all windows: 3, including both titled Notion windows

Interpretation:

- `AXFocusedWindow` is best understood as Notion's current internal focused/main window reference.
- It is not reliable as a complete inventory of restorable Notion windows.
- When some windows are minimized, `AXWindows` and the Window menu can still expose them.
- When all windows are minimized, user observation says `AXFocusedWindow` may become nil; this is plausible and must be verified with `source focus-diagnostics`.
- Window focus/restore should therefore use:
  - `state.json` for intended window/tab identity.
  - Window menu or `AXWindows` for restorable window candidates.
  - `AXFocusedWindow` only as post-action verification after attempting focus/restore.

### A6 Focus Action With Pre/Post Diagnostics

Change:

- `action focus-window` now records:
  - `pre_focus_diagnostics`
  - `focus_action`
  - `post_focus_diagnostics`
  - `focus_validation`
- Validation is split into explicit checks:
  - target present in Window menu
  - target present in `AXWindows`
  - target non-minimized in `AXWindows` after action
  - `AXFocusedWindow` matches target title/frame after action

Command 1:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1000
```

Result 1:

- Log: `logs/v2/20260425-024348-action-focus-window-368a9d43`
- Target: `운영`
- Menu action: `AXPress`
- Pre focused title: `운영`
- Post focused title: `운영`
- Validation: pass
- Checks:
  - target present in Window menu: true
  - target present in `AXWindows`: true
  - target non-minimized in `AXWindows`: true
  - `AXFocusedWindow` matched target: true

Command 2:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1000
```

Result 2:

- Log: `logs/v2/20260425-024354-action-focus-window-874475d7`
- Target: `Privy 다중 계정 연동 기획`
- Menu action: `AXPress`
- Pre focused title: `운영`
- Post focused title: `Privy 다중 계정 연동 기획`
- Validation: pass
- Checks:
  - target present in Window menu: true
  - target present in `AXWindows`: true
  - target non-minimized in `AXWindows`: true
  - `AXFocusedWindow` matched target: true

Interpretation:

- A6 is stronger after this change because focus/restore is no longer judged by a single `AXFocusedWindow` read.
- The target window must also be observable through Window menu and `AXWindows`.
- A minimized candidate can be targeted through the Window menu and then verified as non-minimized plus focused after the action.
- Remaining explicit scenario to test: both Notion windows minimized before running `action focus-window`.

### A6 All-Minimized Restore Test

Initial diagnostic:

- Command: `swift run notion-tabs-v2 source focus-diagnostics`
- Log: `logs/v2/20260425-024556-source-focus-diagnostics-94b0c680`
- `AXFocusedWindow`: nil
- `AXWindows`: 3 windows, all `minimized=true`
  - `운영`
  - `로그, 지표, 통계`
  - `알로콘`
- Window menu document candidates: 3
- `state.json` initially reported 2 windows, then later reported 3 windows including `알로콘`.

Command 1:

```bash
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1500
```

Raw result 1:

- Log: `logs/v2/20260425-024602-action-focus-window-ad97e99b`
- Target: `운영`
- Pre focused: nil
- Post focused: `운영`
- Target present in Window menu: true
- Target present in `AXWindows`: true
- Target non-minimized in `AXWindows`: true
- Frame mismatch:
  - `state.json`: `(x:-552,y:42,w:1424,h:859)`
  - `AXFocusedWindow`: `(x:0,y:41,w:1424,h:859)`
- Initial verdict: ambiguous because frame distance exceeded tolerance.

Follow-up diagnostic:

- Command: `swift run notion-tabs-v2 source focus-diagnostics`
- Log: `logs/v2/20260425-024609-source-focus-diagnostics-4ed43ae0`
- `state.json`: 3 windows
- `AXFocusedWindow`: `운영`, `minimized=false`
- `AXWindows`: `운영` non-minimized, the other two windows minimized.
- Quartz/ScreenCaptureKit also reported `운영` onscreen.

Command 2:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1500
```

Result 2:

- Log: `logs/v2/20260425-024616-action-focus-window-fb03cfc7`
- Target: `로그, 지표, 통계`
- Pre focused: `운영`
- Post focused: `로그, 지표, 통계`
- Validation: pass
- Target present in Window menu: true
- Target present in `AXWindows`: true
- Target non-minimized in `AXWindows`: true
- `AXFocusedWindow` matched target: true

Validation rule update:

- A frame mismatch after minimize/restore is no longer treated as a hard failure when:
  - title matches exactly,
  - target exists in Window menu,
  - target exists in `AXWindows`,
  - target is non-minimized after action,
  - `AXFocusedWindow` title matches the target.
- In that case the result is `soft_pass`.

Retest after rule update:

- Command: `swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1500`
- Log: `logs/v2/20260425-024651-action-focus-window-07bb788c`
- Validation: `soft_pass`
- Reason: target restored and focused title matched, but frame changed after restore.

Persisted state check:

- Command: `swift run notion-tabs-v2 source persisted`
- Log: `logs/v2/20260425-024656-source-persisted-75fc9c38`
- `state.json` still reports `운영` frame as `(x:-552,y:42,w:1424,h:859)`.
- Therefore persisted frame can be stale or represent a pre-restore/off-space layout.

Interpretation:

- All-minimized restore is possible via Window menu.
- `AXFocusedWindow` can be nil before restore and valid after restore.
- `state.json` frame is not reliable enough to be a hard identity check after restore.
- For A6, frame should be a tie-breaker or warning, not a required match, when title/menu/AXWindows/non-minimized/focused-title all agree.

### A8 Tab Observation Bridge

Goal:

- Verify whether persisted tabs can be observed in the focused Notion window without assuming one AX shape.
- This step does not activate tabs.

New command:

```bash
swift run notion-tabs-v2 bridge tab-observation --window-id <window-id>
```

Validation rule:

- The target window must already be focused or at least title-matched by `AXFocusedWindow`.
- The command scans the focused AX tree for all non-empty title/value candidates.
- Each persisted tab title is matched by exact normalized title.
- Preferred tab candidate:
  - role is `AXButton`
  - candidate is in the top tab strip, currently `frame.minY - window.minY <= 44`
  - candidate has `AXPress` or `AXPick`
- Non-preferred same-title candidates such as `AXStaticText`, `AXWebArea`, page-title buttons, and page body text are recorded but do not make the result ambiguous when there is exactly one preferred tab candidate.

Negative control:

- Command: `swift run notion-tabs-v2 bridge tab-observation --window-id 20dfcda0`
- Log: `logs/v2/20260426-134806-bridge-tab-observation-8a8daad3`
- Result: fail
- Reason: requested window `운영` was not focused; focused AX window was `로그, 지표, 통계`.
- Interpretation: the command correctly does not auto-focus and does not pretend to observe another window.

Window 1:

- Focus command: `swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 1500`
- Focus log: `logs/v2/20260426-134812-action-focus-window-06fcb410`
- Focus result: `soft_pass` because frame changed after restore, but title/menu/AXWindows/non-minimized/focused-title matched.
- Observation command: `swift run notion-tabs-v2 bridge tab-observation --window-id 20dfcda0`
- Observation log: `logs/v2/20260426-134835-bridge-tab-observation-e6c5f542`
- Observation result: pass
- Persisted tabs observed: 6/6
- Each persisted tab had exactly one preferred top clickable `AXButton`.

Window 2:

- Initial focus command with `app-first`: `swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1500`
- Initial focus log: `logs/v2/20260426-134840-action-focus-window-d53e73e8`
- Initial result: fail
- Reason: `AXFocusedWindow` temporarily became title `Notion` with nil frame, and `AXWindows` returned only that placeholder.
- Diagnostic log: `logs/v2/20260426-134846-source-focus-diagnostics-747d9621`
- Diagnostic showed Window menu and Quartz still had the target window, so the target was not gone.
- Retry focus command: `swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy menu-only --timeout-ms 2000`
- Retry focus log: `logs/v2/20260426-140553-action-focus-window-ec532db8`
- Retry result: pass
- Observation command: `swift run notion-tabs-v2 bridge tab-observation --window-id bb1a6a8e`
- Observation log before rule refinement: `logs/v2/20260426-140559-bridge-tab-observation-8dcd497c`
- Initial observation result: ambiguous because the active page title button had the same label as the active tab.
- Rule refinement: preferred tab strip threshold tightened from 140px to 44px.
- Observation log after rule refinement: `logs/v2/20260426-140620-bridge-tab-observation-d5f09438`
- Observation result: pass
- Persisted tabs observed: 5/5
- Each persisted tab had exactly one preferred top clickable `AXButton`.

Window 3:

- Focus command: `swift run notion-tabs-v2 action focus-window --window-id e7158fe9 --strategy menu-only --timeout-ms 1500`
- Focus log: `logs/v2/20260426-140625-action-focus-window-662513c1`
- Focus result: pass
- Observation command: `swift run notion-tabs-v2 bridge tab-observation --window-id e7158fe9`
- Observation log: `logs/v2/20260426-140629-bridge-tab-observation-64a74939`
- Observation result: pass
- Persisted tabs observed: 1/1
- The single persisted tab had exactly one preferred top clickable `AXButton`.

Initial interpretation:

- A8 title observation is validated for the current three-window state.
- The earlier `AXWebArea`-only concern was incomplete: when scanning the full focused AX tree, tab strip `AXButton` candidates are present and actionable-looking.
- Same-title noise is real and must be filtered by top tab-strip geometry plus clickability.
- `selected=false` appears on all tab buttons in these runs, including the active tab, so `AXSelected` is not a validated active-tab signal.
- One `app-first` run produced an AX placeholder window named `Notion`; this needs scenario recheck before treating it as a stable rule.
- A9 can proceed only by pressing the preferred top clickable `AXButton` and verifying post-action state changes.

### A6 Placeholder Recheck

Reason:

- The previous A8 run included one failed `app-first` focus attempt where `AXFocusedWindow` and `AXWindows` collapsed to a placeholder-like `AXApplication` titled `Notion`.
- That was only one observation, so it should not be treated as a reliable rule without repetition.

Original failed case:

- Command: `swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 1500`
- Log: `logs/v2/20260426-134840-action-focus-window-d53e73e8`
- Result: fail
- Counts:
  - target present in Window menu: true
  - target present in `AXWindows`: false
  - target non-minimized in `AXWindows`: false
  - focused window matches target: false
- Follow-up diagnostic log: `logs/v2/20260426-134846-source-focus-diagnostics-747d9621`
- Diagnostic evidence:
  - `AXFocusedWindow`: title `Notion`, role `AXApplication`, frame nil
  - `AXWindows`: one item, title `Notion`, role `AXApplication`, frame nil
  - Window menu still had `로그, 지표, 통계`
  - Quartz and ScreenCaptureKit still had the titled target window
  - `state.json` still had the target window

Recheck baseline:

- Command: `swift run notion-tabs-v2 source focus-diagnostics`
- Log: `logs/v2/20260426-140919-source-focus-diagnostics-1978fb50`
- State:
  - focused window: `알로콘`
  - `AXWindows`: `로그, 지표, 통계`, `알로콘`
  - Window menu: 3 document candidates
  - Quartz/ScreenCaptureKit: target windows still visible as live candidates

Recheck commands:

```bash
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 2000
swift run notion-tabs-v2 action focus-window --window-id e7158fe9 --strategy app-first --timeout-ms 2000
swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy app-first --timeout-ms 2000
swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy app-first --timeout-ms 2000
```

Recheck results:

- `bb1a6a8e` from `알로콘`: pass
  - Log: `logs/v2/20260426-140926-action-focus-window-30225ad2`
- `e7158fe9` from `로그, 지표, 통계`: pass
  - Log: `logs/v2/20260426-140931-action-focus-window-de5c8d87`
- `20dfcda0` from `알로콘`: soft_pass
  - Log: `logs/v2/20260426-140935-action-focus-window-c672dd4c`
  - Reason: title matched and target restored, but frame differed from `state.json`.
- `bb1a6a8e` from `운영`: pass
  - Log: `logs/v2/20260426-140944-action-focus-window-3f21349b`

Corrected interpretation:

- The `Notion` placeholder state is real because it was logged, but it was not reproduced in four immediate rechecks.
- It is not justified to claim that `app-first` generally causes the placeholder state.
- Better conclusion:
  - AX can occasionally return an application-level placeholder instead of real windows.
  - When that happens, Window menu, Quartz, ScreenCaptureKit, and `state.json` may still contain the real windows.
  - Treat placeholder as a transient/unknown AX failure mode, not as a deterministic `app-first` behavior.
- Focus logic should handle it with retry/diagnostics rather than switching strategy based on one observation.

### A9 Initial Tab Activation Attempt

Goal:

- Press only the preferred top clickable `AXButton` found by A8.
- Verify tab activation with post-action `state.json` and `AXFocusedWindow`.

New command:

```bash
swift run notion-tabs-v2 action focus-tab --window-id <window-id> [--tab-id <id>|--tab-title <title>] [--timeout-ms N]
```

Pre-state:

- Command: `swift run notion-tabs-v2 source persisted`
- Log: `logs/v2/20260426-143623-source-persisted-34f7a862`
- Window `bb1a6a8e` active tab: `로그, 지표, 통계`
- Target tab: `Docs 작성/제작`

Focused window check:

- Command: `swift run notion-tabs-v2 source focused-window`
- Log: `logs/v2/20260426-143627-source-focused-window-f8db6a94`
- Focused window: `로그, 지표, 통계`

Action command:

```bash
swift run notion-tabs-v2 action focus-tab --window-id bb1a6a8e --tab-title 'Docs 작성/제작' --timeout-ms 2000
```

Result:

- Log: `logs/v2/20260426-143631-action-focus-tab-e8111175`
- Candidate:
  - role: `AXButton`
  - label: `Docs 작성/제작`
  - frame: `(x:443,y:34,w:91,h:36)`
  - nearTop: true
  - clickable: true
  - actions: `[AXPress,AXShowMenu,AXScrollToVisible]`
- `AXPress` returned success.
- Post `state.json` active title remained `로그, 지표, 통계`.
- Post `AXFocusedWindow` title remained `로그, 지표, 통계`.
- Result: fail
- Reason: `AXPress` on the preferred tab button did not activate the tab.

Post-observation:

- Command: `swift run notion-tabs-v2 bridge tab-observation --window-id bb1a6a8e`
- Log: `logs/v2/20260426-143642-bridge-tab-observation-b676a4b1`
- Result: pass
- The same preferred `AXButton` candidate for `Docs 작성/제작` was still present.

Interpretation:

- A8 observation is valid: the tab button candidate exists and is uniquely identifiable.
- A9 activation by `AXPress` is not validated.
- The existence of `AXPress` on a Notion tab button is not enough to prove it triggers tab activation.
- Next activation experiment should compare:
  - `AXPress` only
  - `AXScrollToVisible` then `AXPress`
  - coordinate click at the preferred button center
- Coordinate click must still be treated as an experiment and verified with the same post-state checks.

### A9 Follow-up Activation Strategies

Strategy support:

- `focus-tab` now accepts:
  - `--strategy press-only`
  - `--strategy scroll-then-press`
  - `--strategy coordinate-click`

A9-2 command:

```bash
swift run notion-tabs-v2 action focus-tab --window-id bb1a6a8e --tab-title 'Docs 작성/제작' --strategy scroll-then-press --timeout-ms 2000
```

A9-2 result:

- Log: `logs/v2/20260426-143921-action-focus-tab-e9b4e13c`
- Candidate:
  - role: `AXButton`
  - label: `Docs 작성/제작`
  - frame: `(x:443,y:34,w:91,h:36)`
  - actions: `[AXPress,AXShowMenu,AXScrollToVisible]`
- `AXScrollToVisible` returned true.
- `AXPress` returned true.
- Post `state.json` active title remained `로그, 지표, 통계`.
- Post `AXFocusedWindow` title remained `로그, 지표, 통계`.
- Result: fail.

A9-3 command:

```bash
swift run notion-tabs-v2 action focus-tab --window-id bb1a6a8e --tab-title 'Docs 작성/제작' --strategy coordinate-click --timeout-ms 2000
```

A9-3 result:

- Log: `logs/v2/20260426-143949-action-focus-tab-196e215d`
- Candidate:
  - role: `AXButton`
  - label: `Docs 작성/제작`
  - frame: `(x:443,y:34,w:91,h:36)`
  - click point: `(488,52)`
- CGEvent mouse down/up objects were created and posted.
- Post `state.json` active title remained `로그, 지표, 통계`.
- Post `AXFocusedWindow` title remained `로그, 지표, 통계`.
- Result: fail.

Interpretation:

- Three activation strategies failed on the same observed preferred tab candidate:
  - `AXPress`
  - `AXScrollToVisible` + `AXPress`
  - center coordinate click
- This does not invalidate A8 observation; it means the observed `AXButton` may not be the actual interactive surface for tab activation, or event delivery/click coordinates need further validation.
- Before trying more tab activation variants, the next closed check should verify:
  - target window is actually onscreen and topmost enough to receive CGEvents,
  - the click point is not covered by another window/layer,
  - a coordinate click on a known harmless visible control in Notion can produce a verifiable effect.

### A9 Coordinate Delivery Check

Reason:

- The first coordinate-click attempt failed even though the candidate point looked correct.
- We needed to verify whether the click point was actually delivered to Notion.

New command:

```bash
swift run notion-tabs-v2 source point-diagnostics --x <x> --y <y>
```

Point diagnostic:

- Command: `swift run notion-tabs-v2 source point-diagnostics --x 488 --y 52`
- Log: `logs/v2/20260426-144308-source-point-diagnostics-c4080727`
- Result:
  - top window at `(488,52)` was `iTerm2`, not Notion.
  - Notion was second at that point.
- Interpretation:
  - The earlier coordinate-click likely clicked the terminal window, not Notion.
  - `AXFocusedWindow` can still report Notion while the terminal is visually/topmost over the click point.

Code change:

- `coordinate-click` now activates Notion with `activateIgnoringOtherApps` before posting the mouse event.

Retest command:

```bash
swift run notion-tabs-v2 action focus-tab --window-id bb1a6a8e --tab-title 'Docs 작성/제작' --strategy coordinate-click --timeout-ms 2500
```

Retest result:

- Log: `logs/v2/20260426-144332-action-focus-tab-b9594221`
- Click point: `(488,52)`
- Result: pass
- Post `AXFocusedWindow` title changed to `Docs 작성/제작`.
- Post `state.json` active title still remained `로그, 지표, 통계` within the timeout.

Follow-up checks:

- `swift run notion-tabs-v2 source persisted`
  - Log: `logs/v2/20260426-144343-source-persisted-a793d080`
  - `state.json` still reported Window 2 active title as `로그, 지표, 통계`.
- `swift run notion-tabs-v2 source focused-window`
  - Log: `logs/v2/20260426-144346-source-focused-window-7775a15e`
  - AX focused title was `Docs 작성/제작`.
- `swift run notion-tabs-v2 source persisted`
  - Log: `logs/v2/20260426-144359-source-persisted-7ece187b`
  - `state.json` still had not updated after about 25 seconds.

Corrected interpretation:

- Coordinate click can activate a Notion tab when Notion is actually frontmost at the click point.
- `state.json` activeTitle is not a reliable realtime post-action oracle for tab activation.
- For A9, immediate success should be based on `AXFocusedWindow` title matching the target.
- `state.json` can remain useful as a tab inventory source, but not as the immediate active-tab truth source.

### A9 Repeated Multi-Window Tab Activation

Reason:

- User asked to repeat the successful coordinate-click experiment across more windows and more tabs.
- We also needed to verify that stale `state.json` activeTitle does not break subsequent tab experiments.

Code adjustment:

- `action focus-tab` no longer requires `state.json` activeTitle to match `AXFocusedWindow` before pressing a tab.
- If all persisted tabs for the requested window are observed in the focused AX tree, the window is accepted as the target even when persisted activeTitle is stale.
- `bridge tab-observation` was adjusted similarly: if all persisted tabs are observed, focused-title mismatch alone does not fail the bridge.

Window 2 setup:

- Command: `swift run notion-tabs-v2 action focus-window --window-id bb1a6a8e --strategy menu-only --timeout-ms 1500`
- Log: `logs/v2/20260426-144651-action-focus-window-cb912a33`
- Result: pass

Window 2 repeated tab activation:

- Target: `Alpha 포인트 리더보드`
  - Log: `logs/v2/20260426-144657-action-focus-tab-758d81f6`
  - Result: pass
  - Post AX title: `Alpha 포인트 리더보드`
- Target: `Privy 다중 계정 연동 기획`
  - Log: `logs/v2/20260426-144705-action-focus-tab-aa3ef1f5`
  - Result: pass
  - Post AX title: `Privy 다중 계정 연동 기획`
- Target: `Versus Liquidity Provider (VLP)`
  - Log: `logs/v2/20260426-144713-action-focus-tab-4c03b09e`
  - Result: pass
  - Post AX title: `Versus Liquidity Provider (VLP)`

Window 2 observation:

- `state.json` lagged/staled during these transitions.
- `preActive`/`postActive` in the action logs stayed at the older persisted title, while `AXFocusedWindow` changed correctly.

Window 1 setup:

- Command: `swift run notion-tabs-v2 action focus-window --window-id 20dfcda0 --strategy menu-only --timeout-ms 2000`
- Log: `logs/v2/20260426-144721-action-focus-window-1431f4e0`
- Result: soft_pass
- Reason: title matched and window restored, but frame differs from stale persisted frame.

Window 1 repeated tab activation:

- Target: `Phase 1 런칭 QA list`
  - Log: `logs/v2/20260426-144728-action-focus-tab-3044c3e8`
  - Result: pass
  - Post AX title: `Phase 1 런칭 QA list`
- Target: `Leaderboard + Gamification`
  - Log: `logs/v2/20260426-144736-action-focus-tab-8faf9e7e`
  - Result: pass
  - Post AX title: `Leaderboard + Gamification`
- Target: `Points 기획`
  - Log: `logs/v2/20260426-144745-action-focus-tab-0549ec75`
  - Result: pass
  - Post AX title: `Points 기획`

Final checks:

- `swift run notion-tabs-v2 source focused-window`
  - Log: `logs/v2/20260426-144754-source-focused-window-3251b60b`
  - AX focused title: `Points 기획`
- `swift run notion-tabs-v2 source persisted`
  - Log: `logs/v2/20260426-144754-source-persisted-b3c3a0bc`
  - `state.json` still reported Window 1 active as `운영`.
  - `state.json` reported Window 2 active as `Versus Liquidity Provider (VLP)`, showing it can update eventually for some windows but not reliably in realtime.
- `swift run notion-tabs-v2 bridge tab-observation --window-id 20dfcda0`
  - Log: `logs/v2/20260426-144818-bridge-tab-observation-baccfda6`
  - Result: pass
  - All 6 persisted tabs were observed even though the focused title was `Points 기획`.

Interpretation:

- Coordinate-click activation is now validated across 2 windows and 6 tab transitions.
- Immediate tab activation truth should be `AXFocusedWindow`, not `state.json`.
- `state.json` remains useful as tab inventory, but activeTitle can lag or remain stale after tab switches.
- The tab-observation bridge must tolerate stale persisted activeTitle when all persisted tabs are observed in the focused AX tree.

### User-Facing CLI Commands

Goal:

- Keep diagnostics available, but expose a small validated user path.

New user-facing commands:

```bash
swift run notion-tabs-v2 list
swift run notion-tabs-v2 focus-window --window-id <id> [--timeout-ms N]
swift run notion-tabs-v2 focus-tab --window-id <id> [--tab-id <id>|--tab-title <title>] [--timeout-ms N]
```

Defaults:

- `focus-window` uses Window menu only.
- `focus-tab` uses coordinate click on the preferred top tab-strip `AXButton`.
- `focus-tab` brings Notion frontmost and raises the focused AX window before posting the coordinate click.

Initial user command tests:

- `swift run notion-tabs-v2 list`
  - Log: `logs/v2/20260426-145739-list-ab25122f`
  - Result: pass
- `swift run notion-tabs-v2 focus-window --window-id 20dfcda0 --timeout-ms 2000`
  - Log: `logs/v2/20260426-145745-action-focus-window-c644da87`
  - Result: soft_pass
  - Reason: target focused by title, but persisted frame was stale.
- `swift run notion-tabs-v2 focus-tab --window-id 20dfcda0 --tab-title '운영' --timeout-ms 2500`
  - Log: `logs/v2/20260426-145751-action-focus-tab-f00f2194`
  - Result: fail
  - Reason: click point was not guaranteed to be delivered to the intended Notion window.

Fix:

- Before coordinate-click, `focus-tab` now:
  - activates Notion with `activateIgnoringOtherApps`,
  - performs `AXRaise` on the focused AX window,
  - waits briefly before posting the mouse event.

Retest:

- `swift run notion-tabs-v2 focus-window --window-id 20dfcda0 --timeout-ms 2000`
  - Log: `logs/v2/20260426-145830-action-focus-window-e501bf74`
  - Result: soft_pass
- `swift run notion-tabs-v2 focus-tab --window-id 20dfcda0 --tab-title '운영' --timeout-ms 3000`
  - Log: `logs/v2/20260426-145836-action-focus-tab-0ce076dc`
  - Result: pass
  - Post AX title: `운영`
- `swift run notion-tabs-v2 list`
  - Log: `logs/v2/20260426-145845-list-60aec673`
  - Result: pass
  - Focused AX title: `운영`

Interpretation:

- The user-facing path is now:
  - use `list` to inspect inventory,
  - use `focus-window` to bring the target window into focus,
  - use `focus-tab` to activate a tab by id or exact title.
- `list` intentionally displays both persisted active marker `*` and AX focused marker `>` because they can diverge.
