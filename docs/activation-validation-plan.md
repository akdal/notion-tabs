# Activation Validation Plan

## Goal

Validate that the helper can:

- activate a specific Notion window
- then activate a specific tab inside that window

Target conditions:

- normal visible window
- inactive Space window
- minimized window

## Current Test Command

```bash
swift run notion-tabs-poc activate-window-persisted --window <window-index> --pause-ms 700 --strategy menu-only
swift run notion-tabs-poc activate-window-persisted --window <window-index> --pause-ms 700 --strategy app-first
swift run notion-tabs-poc activate-persisted --window <window-index> --tab <tab-index> --pause-ms 700
swift run notion-tabs-poc activate-persisted --window <window-index> --tab <tab-index> --pause-ms 700 --strategy app-first
```

Notes:

- The indices come from `persisted-list`.
- The command resolves the actual target titles internally from the persisted snapshot.
- `pause-ms` now acts as the maximum wait budget per activation step, with early exit as soon as the expected state is observed.
- Activation strategy options:
  - `menu-only`: baseline `Window` menu selection
  - `app-first`: `NSRunningApplication.activate(options: [.activateAllWindows])` first, then `Window` menu selection

## Current Mechanism

1. Read the target from the persisted Notion snapshot if needed.
2. Resolve the selected window's current active title.
3. Optionally activate Notion first through `NSRunningApplication.activate(options: [.activateAllWindows])`.
4. Find the matching entry in Notion's `Window` menu.
5. Activate that window through the menu item.
6. Read the focused window's tabs via AX.
7. Press the target tab via AX.
8. Verify that the final focused window title matches the requested tab title.

Current tab activation order:

1. `AXScrollToVisible` when available
2. `AXPress`
3. fallback `CGEvent` click at the tab element's center when AX action alone does not confirm

## Staged Hybrid Plan

Problem statement:

- `state.json` is good for initial target discovery
- `state.json` is too stale to trust for post-activation current tab state
- AX is the better source for current live tab state after the window is activated

Planned role split:

1. Use `state.json` only to identify the target window and target tab.
2. Activate the target window.
3. Re-read the focused window through AX.
4. Use AX, not `state.json`, to determine:
   - the currently selected tab
   - the current tab order exposed in the live window
5. Use staged fallback for tab movement:
   - direct AX tab press
   - `Cmd+1...9` when the target index is in range
   - `Window > Show Previous Tab / Show Next Tab` for longer strips

Expected advantages:

- stale persisted active-tab state no longer drives fallback decisions
- hidden-tab navigation can use the live AX order of the focused window
- fallback decisions become aligned with the actual active window state

Expected risks:

- AX may fail to expose a stable live tab list under overlays or narrow layouts
- AX-selected-state may be missing even when the tab strip is visible
- shortcut fallback may still be context-sensitive depending on current Notion UI state

Validation stages:

### Stage 1: AX live state read

Goal:

- confirm that after window activation the focused window's current tab list and selected tab can be read from AX

Pass:

- AX returns a non-empty tab list for the activated window
- the current selected tab or current focused title can be derived consistently

Fail:

- AX returns no tabs or inconsistent current-state information

If pass:

- continue to Stage 2

If fail:

- keep `state.json` as discovery only and add explicit overlay / unsupported-state detection

### Stage 2: `Cmd+1...9` fallback from AX-derived state

Goal:

- use AX-derived live target/current state to decide when shortcut fallback should run

Pass:

- 1..9 tab cases improve or remain stable across repeated runs

Fail:

- shortcut fallback causes cross-window drift or no measurable improvement

If pass:

- keep shortcut fallback ahead of menu-based tab navigation

If fail:

- demote shortcut fallback or restrict it to a narrower set of windows/states

### Stage 3: `Show Previous / Next Tab` fallback from AX-derived state

Goal:

- support hidden and 10+ tab cases by using the live focused window state instead of persisted active-tab state

Pass:

- 10+ tab cases succeed repeatedly

Fail:

- repeated menu tab navigation still lands on the wrong tab or loses the correct window context

If pass:

- keep menu tab navigation as the long-strip fallback

If fail:

- add stronger step-by-step confirmation after each menu navigation or reconsider a different overflow-tab strategy

## Expected Success Signal

The command prints:

- `matchedWindow=true`
- `matchedTab=true`

and exits with code `0`.

For window-only testing, the success signal is:

- `Activate-window summary`
- `matchedWindow=true`

## Manual Validation Scenarios

Validation rule:

- Always start by running `swift run notion-tabs-poc persisted-list`.
- Do not trust previous window/tab indices after activation tests have already moved tabs around.
- Use the fresh `persisted-list` output as the only valid baseline before the next verification round.

Recommended tab-validation order:

1. Run `persisted-list` first and record the current windows, active titles, and tab counts.
2. Run a full per-window sweep:
   - for each window, try every tab index once
3. Run additional random jumps:
   - pick random window/tab pairs after the sweep
   - confirm that non-sequential movement also works
4. If a case fails, immediately re-run `persisted-list` before interpreting the failure.

Interpretation rule:

- If `persisted-list` was not refreshed first, the result is not a clean validation result.
- If activation changes the live state, treat the previous indices as stale until a fresh `persisted-list` is taken.

## Product-Oriented Validation

Rationale:

- a full sequential sweep is useful for debugging, but it is stricter than the actual product need
- the real user action is a single jump from the current state to one chosen window/tab

Primary validation mode:

1. Run `swift run notion-tabs-poc persisted-list`.
2. Pick one window/tab pair.
3. Run exactly one activation attempt.
4. Re-run `persisted-list`.
5. Pick another window/tab pair from the fresh state.

Recommended sample size:

- at least 10 single-shot jumps across different windows

Recommended mix:

- visible window, visible tab
- visible window, hidden/overflow tab
- inactive-Space window
- minimized window
- 1..9 tab
- 10+ tab

Pass criteria for product-oriented validation:

- strong pass:
  - at least 8/10 single-shot jumps succeed
  - each major category above is represented
- soft pass:
  - at least 6/10 single-shot jumps succeed
  - failures are concentrated in known edge cases such as overlays or very long tab strips

Fail criteria:

- repeated failures in ordinary visible-window single-shot jumps
- failures are not concentrated in edge cases
- success depends too heavily on retrying the same target

Interpretation:

- if product-oriented validation passes, the PoC is good enough to move into a lightweight background or menu bar UI prototype
- if it fails, the next work should stay focused on activation reliability, not UI

### Scenario 1: Normal visible window

1. Run `swift run notion-tabs-poc persisted-list`.
2. Pick a window and a tab from the output.
3. Run `activate-persisted` with those indices.

### Scenario 2: Inactive Space window

1. Move one Notion window to another Space.
2. Keep the current Space active.
3. Run `persisted-list` and choose a tab from the inactive-Space window.
4. Run `activate-persisted`.
5. Confirm that macOS switches to the target window and the requested tab becomes active.

### Scenario 3: Minimized window

1. Minimize a Notion window.
2. Run `persisted-list` and choose a tab from that window.
3. Run `activate-persisted`.
4. Confirm that the window is restored and the requested tab becomes active.

## Current Interpretation

Current observed result:

- `menu-only`
  - normal visible window: can pass
  - minimized window: can pass
  - inactive Space window: unreliable
- `app-first`
  - normal visible window: passes
  - minimized window: passes
  - inactive Space window: passes in current user validation

Interpretation:

- `app-first` is the current best activation candidate.
- Activating the application first appears to give Mission Control / Spaces enough system context to bring the target window forward even when it lives on another Space.
- For tab activation, `AXPress` alone was not reliable enough in current testing.
- `AXScrollToVisible -> AXPress` materially improved reliability for tabs in a long tab strip.
- A coordinate-click fallback now exists for further recovery when AX action does not confirm.
- The current weakness is UX quality rather than binary success:
  - a visible Notion window may briefly take focus before the hidden target window is restored
  - window switching is slower than desired
  - tab switching is slower than desired
  - the transition does not always feel like a direct jump to the target window

## Recent Experiment Result

Validated on April 24, 2026:

- target case: persisted `window=3`, `tab=7`
- target tab title: `Versus 프로덕트 주간 회의`
- previous failing behavior:
  - target window activation passed
  - target tab element was found
  - `AXPress` alone did not consistently switch the tab
- updated behavior:
  - `verify --window 1 --range 7-7 --pause-ms 700` passed
  - `repeat-activate-persisted --window 3 --tab 7 --repeats 3 --pause-ms 700 --strategy app-first` passed `3/3`

Interpretation:

- the problem was not tab discovery itself
- the more reliable path is now:
  - activate app/window
  - ensure the tab is scrolled into view
  - press the tab
  - use click fallback only if confirmation still does not arrive

## Current Product Note

- Window and tab discovery: current preferred candidate remains `state.json`.
- Activation: current preferred candidate is `app-first`.
- The next optimization target is not correctness first; it is reducing visible intermediate focus changes and latency.

## Optimization Plan

### Goal

Improve the `app-first` path without regressing its current success on:

- visible windows
- minimized windows
- inactive-Space windows

### Problem Breakdown

Current user-observed issues:

- hidden target windows can cause a different visible Notion window to receive focus first
- window switching feels slower than desired
- tab switching feels slower than desired
- the overall transition does not always feel like a direct jump to the requested target

### Hypotheses To Test

#### 1. Reduce fixed sleeps

- Current path uses fixed `pause-ms` waits between steps.
- Hypothesis:
  - part of the latency is self-inflicted by conservative sleeps
  - replacing fixed waits with short retry loops against actual state may improve speed without reducing success

Validation:

- compare `pause-ms` values such as `700`, `400`, `250`
- then replace fixed waits with:
  - poll until focused window changes
  - poll until target tab appears in AX
  - stop early as soon as the expected state is reached

#### 2. Skip redundant raise steps

- Current path can perform:
  - app activation
  - Window menu selection
  - AXRaise on the focused window
- Hypothesis:
  - once `app-first` and Window menu selection have already succeeded, `AXRaise` may be unnecessary in some cases
  - removing redundant raise calls may reduce extra focus churn

Validation:

- compare:
  - `app-first + menu + raise`
  - `app-first + menu`

#### 3. Separate window-only and tab-only timing

- The current path chains window activation and tab activation in one flow.
- Hypothesis:
  - window activation is the dominant latency source
  - tab activation itself may already be relatively cheap once the correct window is focused

Validation:

- measure window-only activation first
- measure window+tab activation second
- compare the incremental cost of the tab step

#### 4. Detect minimized or hidden targets before app activation

- Current path activates the whole Notion app first, which can surface a non-target visible window.
- Hypothesis:
  - if the target window is minimized or otherwise not onscreen, we may need a more specific restore step after app activation and before tab activation
  - if the target is already onscreen, a lighter path may be enough

Validation:

- compare current persisted bounds and ScreenCaptureKit onscreen state with observed focus behavior
- classify target state before activation:
  - onscreen visible
  - minimized / hidden
  - inactive Space

#### 5. Prefer direct success over visual smoothness for v1

- There may be no public API path that guarantees a perfectly direct jump to another app's exact window across Spaces.
- Hypothesis:
  - we may reach a practical ceiling where correctness is good enough but visual polish remains imperfect

Validation:

- if `app-first` remains the only reliable cross-Space path, keep it as the product default
- then optimize latency and visible churn incrementally rather than chasing a fully direct jump first

### 6. Live unique-id search

- Focused window inspection currently shows:
  - `AXTitle`
  - `AXFrame`
  - `AXDocument` (empty)
  - state flags such as `AXMain` and `AXFocused`
- It does not show:
  - `AXIdentifier`
  - `AXWindowNumber`
- Implication:
  - there is no stable live-side unique ID available from the focused AX window in the current environment
  - the remaining bridge problem must be solved through menu/title/frame matching or a different public API surface

### 7. Window menu item inspection

- `Window` menu items expose `AXIdentifier`, but it is the same value for all items: `makeKeyAndOrderFront:`
- `AXMenuItemMarkChar` only indicates the current selected item and is not a stable identity
- Shortcut fields are empty in the current test
- Implication:
  - the menu itself does not provide a unique per-window key
  - title-based matching remains unavoidable on the live menu side

### 8. Official activation API research

- Apple public activation options reviewed:
  - `NSRunningApplication.activate(options:)`
  - `NSRunningApplication.activate(from:options:)`
  - `NSApplication.yieldActivation(to:)`
  - `NSWindow.orderFrontRegardless()`
- Result:
  - `NSRunningApplication.activate(options:)` is the main public API for app activation
  - `activate(from:options:)` / `yieldActivation(to:)` are cooperative and require the target app to participate
  - `NSWindow.orderFrontRegardless()` is for a window owned by the app itself
  - no public Apple API was found that guarantees "bring this specific existing window of another app to the front across an inactive Space" as a single direct operation
- Implication:
  - the current `app-first` path is already the closest public-api candidate
  - remaining work is bridge accuracy and UX smoothing, not swapping in a missing Apple activation API

### Recommended Execution Order

1. Replace fixed waits with short state-based polling.
2. Test whether `AXRaise` can be removed from the `app-first` path.
3. Add simple timing logs for:
   - app activation
   - window selection
   - tab activation
4. Compare visible / minimized / inactive-Space cases separately.
5. Keep `menu-only` only as a regression baseline, not as the main product path.
