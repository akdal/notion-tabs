# Background Discovery Matrix

## Goal

Validate which non-visual methods can retrieve:

- the full list of open Notion windows
- the full tab list for each window
- while the helper app stays in the background

Visual capture/OCR is explicitly rejected as a product approach.

## Methods Tested

### 1. Process discovery via `NSWorkspace` / `NSRunningApplication`

- Purpose: confirm that Notion is running and obtain the PID.
- Result: works reliably.
- What it gives:
  - running app instance
  - PID
  - bundle identifier
- What it does not give:
  - window list
  - tab list
- Verdict: required baseline, not a window/tab source.

### 2. Accessibility app-level `AXWindows`

- Purpose: enumerate Notion windows directly from the AX application object.
- Result:
  - works for visible/focused windows
  - can return fewer windows than are actually open when Space state changes
  - observed to be state-dependent
- What it gives:
  - window objects
  - window titles
  - access to tab scanning for returned windows
- What it does not reliably give:
  - all open windows across Spaces
- Verdict: useful, but not sufficient as the only source.

### 3. Accessibility `AXChildren` / `AXChildrenInNavigationOrder`

- Purpose: find hidden top-level windows by traversing app children instead of `AXWindows`.
- Result:
  - no extra cross-Space windows were discovered beyond what AX already exposed
  - mostly returns the same top-level app objects: window, menu bar, function row
- Verdict: no meaningful improvement over `AXWindows`.

### 4. Accessibility tab-specific APIs (`kAXTabsAttribute`, tab roles)

- Purpose: see whether Notion exposes official tab containers or tab arrays.
- Result:
  - no `AXTabs` exposure found
  - no `AXTab` / `AXTabGroup` role hits found in the scanned tree
- Verdict: Notion does not currently expose its tab strip through the canonical AX tab API in this environment.

### 5. Accessibility `AXSections`

- Purpose: check whether window sections expose tab-strip metadata indirectly.
- Result:
  - `AXWindow` reports `AXSections`
  - returned section elements did not expose usable role/title data in our probing
- Verdict: inconclusive, but currently not actionable.

### 5b. Focused `AXWindow` attribute inspection

- Purpose: check whether the live focused Notion window exposes a stable identifier beyond title/frame.
- Result:
  - `AXTitle` is present
  - `AXFrame` is present
  - `AXDocument` is present but empty in the current test
  - `AXIdentifier` was not present
  - `AXWindowNumber` was not present
  - `AXMain`, `AXFocused`, `AXMinimized`, `AXFullScreen` are present as state flags
- Verdict:
  - no stable live-side unique window ID was found in the focused AX window attributes
  - live activation still needs a title/frame/menu bridge

### 6. Notion `Window` menu

- Purpose: read the list of open Notion windows without relying on `AXWindows`.
- Result:
  - consistently returns the open window titles we care about
  - continues to list windows even when direct AX window enumeration becomes incomplete
- What it gives:
  - stable window titles
  - ordering of currently open windows
- What it does not give:
  - tab list per window
- Verdict: best current source for full window list.

### 6b. `Window` menu item attributes

- Purpose: inspect whether menu items expose a stable per-window identifier that can replace title matching.
- Result:
  - `AXIdentifier` is present, but every candidate item exposed the same value: `makeKeyAndOrderFront:`
  - `AXMenuItemMarkChar` reflects the current selected item, but is not a stable identity
  - `AXMenuItemCmdChar`, `AXMenuItemCmdVirtualKey`, and related shortcut fields were empty in the current test
  - `AXFrame` was not useful for identity; it was effectively a zero-sized menu coordinate
- Verdict:
  - `Window` menu items do not currently expose a stable unique per-window identifier
  - title remains the only practical menu-side selector

### 7. Quartz Window Services (`CGWindowListCopyWindowInfo`)

- Purpose: detect Notion window server surfaces independently of Accessibility.
- Result:
  - large Notion window candidates can be found across Spaces
  - titles are often empty
  - bounds are available
- What it gives:
  - window count candidates
  - window IDs
  - bounds
  - onscreen hints
- What it does not give:
  - tab list
  - reliable document/window titles
- Verdict: strong supporting source for whole-window discovery, but not enough alone.

### 8. ScreenCaptureKit window enumeration (`SCShareableContent`)

- Purpose: ask macOS for shareable window metadata without relying on Accessibility.
- Result:
  - returns both Notion windows with stable window IDs, titles, and frames
  - `onScreenWindowsOnly: true` returns only the current onscreen window
  - `onScreenWindowsOnly: false` returns both the onscreen and inactive-Space window
  - `SCWindow.isOnScreen` and `SCWindow.isActive` explicitly distinguish the inactive window in the current test
- What it gives:
  - window titles
  - window IDs
  - frame
  - onscreen/inactive signal
- What it does not give:
  - tab list
- Verdict: best current passive source for the full Notion window list across Spaces.

### 9. AppKit visible window numbers (`NSWindow.windowNumbersWithOptions`)

- Purpose: query macOS for visible window numbers across applications and Spaces.
- Result:
  - with `.allApplications` + `.allSpaces`, Notion content windows were found
  - requires a second lookup step to attach titles/bounds via Core Graphics window info
- What it gives:
  - window numbers for visible windows
  - cross-app / all-Spaces visibility when combined with the documented options
- What it does not give:
  - tab list
  - hidden or non-visible windows
- Verdict: useful supporting source for full visible window enumeration, but ScreenCaptureKit is richer.

### 10. Persisted Notion session state (`~/Library/Application Support/Notion/state.json`)

- Purpose: inspect whether Notion itself persists the current open windows and tabs locally.
- Result:
  - `history.appRestorationState.windows[]` contains:
    - per-window bounds
    - per-window active tab
    - full tab arrays with titles and URLs
  - current test data matched the observed two-window setup, including the inactive-Space window
  - file modification time updates while Notion is running
  - active-tab changes were observed to propagate with delay rather than instantly
- What it gives:
  - full window list
  - full per-window tab list
  - active tab per window
  - bounds that align with observed windows
- What it does not guarantee:
  - immediate consistency
  - long-term format stability
  - official API support from Notion
- Verdict: strongest current passive source for full window + tab state, but it is an internal implementation detail and appears eventually consistent.

### 11. Window menu + Accessibility activation (`verify-list`)

- Purpose: use the `Window` menu to iterate each open Notion window, then scan that focused window's tabs via AX.
- Result:
  - works reliably in repeated runs
  - currently the only verified way to get all windows and each window's tabs
- Cost:
  - activates Notion windows
  - not acceptable as final product interaction if the helper must remain passive
- Verdict: best diagnostic path, not yet acceptable as the final background UX path.

### 12. Visual capture / OCR

- Purpose: explored briefly as a technical possibility.
- Result:
  - technically possible in some states
  - rejected as a product approach
- Verdict: not to be used.

## Current Conclusion

The strongest non-visual combination so far is:

1. `NSRunningApplication` for process identity
2. `SCShareableContent` for the passive full open-window list across Spaces
3. `state.json` as the strongest passive source for full window + tab state, with eventual-consistency caveats
4. `Window` menu as a secondary cross-check of open windows
5. `CGWindowListCopyWindowInfo` as a lower-level cross-check that large Notion windows exist in the window server
6. Accessibility for tab extraction, but only for windows currently exposed through AX

## Final Candidate Approaches

### Candidate A: `state.json` only

- Use Notion's persisted `state.json` as the source of truth for:
  - open windows
  - per-window tab list
  - active tab
- Strength:
  - currently the strongest passive full snapshot source
  - works across inactive Spaces in the current environment
- Risk:
  - eventual consistency
  - internal file format may change

### Candidate B: AX + persisted-state hybrid

- Use AX as the freshest source for windows currently exposed in the live accessibility tree.
- Use `state.json` as the fallback source for windows/tabs not currently exposed through AX.
- Strength:
  - can potentially reduce perceived latency for the active/visible window set
- Risk:
  - source conflict resolution is required
  - AX polling cost and complexity must be validated before productizing

Current product-direction note:

- The current preferred implementation candidate is `state.json` first.
- AX polling remains a recorded follow-up candidate, not the current default choice.

## Observed State Matrix

### State A: Both target windows exposed through AX

Observed result:

- `AXWindows`: 2
- `Window` menu: 2
- Quartz window candidates: 2
- Tab extraction: works for both windows without extra activation

Interpretation:

- If both windows are currently exposed in the accessibility tree, AX alone is enough.

### State B: Notion in background (`frontmost=false`, `hidden=false`)

Observed result:

- `AXWindows`: 1
- `SCShareableContent` all: 2
- `SCShareableContent` onscreen-only: 1
- `Window` menu: 2
- Quartz window candidates: 2

Interpretation:

- Window list remains recoverable in background.
- ScreenCaptureKit remains stable in background and can still distinguish onscreen vs inactive windows.
- AX can shrink even while the app is still running and visible.

### State C: Notion frontmost, but one target window not exposed in the current AX view

Observed result:

- `frontmost=true`
- `AXWindows`: 1
- `SCShareableContent` all: 2
- `SCShareableContent` onscreen-only: 1
- `Window` menu: 2
- Quartz window candidates: 2

Interpretation:

- Frontmost status alone does not guarantee full AX window enumeration.
- This is consistent with an inactive-Space or otherwise non-exposed window state.

## Official Documentation Signal

What Apple documentation clearly says:

- `kAXWindowsAttribute` is described as an array of an application's windows.
- `Quartz Window Services` includes onscreen windows and offscreen windows used by running applications.
- `SCShareableContent.getExcludingDesktopWindows(... onScreenWindowsOnly: ...)` explicitly supports filtering onscreen-only windows.
- `SCWindow` exposes `title`, `windowID`, `frame`, `isOnScreen`, and `isActive`.

What I have not found in Apple documentation:

- An explicit statement that `kAXWindowsAttribute` is Space-aware or Space-limited.
- An explicit statement that `kAXWindowsAttribute` excludes inactive-Space windows.

So the AX/Spaces relationship is currently an observed behavior in this environment, not something I can point to in Apple docs as a guaranteed rule.

## Practical Validation Procedure For Inactive Spaces

To validate whether a missing AX window is caused by inactive Space state:

1. Keep two Notion windows open with distinct titles.
2. Run `swift run notion-tabs-poc window-sources`.
3. Move one window to another macOS Space.
4. Without activating that other Space, run `swift run notion-tabs-poc window-sources` again.
5. Compare:
   - if `AXWindows` drops but `Window` menu and Quartz remain stable, the missing window is still open but not currently exposed through AX

Current evidence strongly points to that behavior.

## What Is Proven

- We can reliably know that Notion is running.
- We can reliably recover the open window list better than `AXWindows` alone.
- We can reliably read tabs from a window once that window is exposed through AX.
- We can reliably activate a chosen window and tab.
- We can passively read a full two-window / multi-tab snapshot from Notion's persisted `state.json` in the current environment.

## What Is Not Yet Proven

- Whether `state.json` remains fresh enough for product-grade realtime usage under rapid tab churn.
- Whether the persisted state format is stable across Notion updates.
- A fully official/passive API for cross-Space per-window tab lists.

## Best Current Answer

- Full window list in background: `yes`, with `Window` menu plus Quartz as support.
- Best passive full window list in background: `yes`, with ScreenCaptureKit first, Window menu and Quartz as cross-checks.
- Best passive full per-window tab list in the current environment: `state.json`, with eventual-consistency and format-stability risks.

## Activation Note For Inactive Spaces

Observed activation result:

- visible window: current `Window` menu + AX path works
- minimized window: current `Window` menu + AX path works
- inactive-Space window: current path is not yet reliable enough

Official API signal found so far:

- `NSRunningApplication.activate(options:)` is the official public API to request app activation.
- Apple explicitly notes that activation is only attempted and is not guaranteed.
- `NSWindow.CollectionBehavior.moveToActiveSpace` and `.canJoinAllSpaces` are official Space-related controls, but they are properties of windows owned by the app itself.
- Those controls are useful when building your own AppKit window, not when trying to retarget another application's existing window behavior.

Practical implication:

- There is a clear official API for activating the Notion application.
- There is not yet a clear public Apple API that guarantees "activate this specific existing window of another app even if it lives in an inactive Space".
- If that exact behavior is mandatory, we should treat it as a separate feasibility problem from ordinary activation.

## Activation Strategy Result

Two activation strategies were tested against the persisted window/tab snapshot.

### Strategy 1: `menu-only`

- Mechanism:
  - select target through Notion's `Window` menu
  - then use AX to raise / select the tab
- Result:
  - works for some visible and minimized cases
  - not reliable enough for inactive-Space windows

### Strategy 2: `app-first`

- Mechanism:
  - call `NSRunningApplication.activate(options: [.activateAllWindows])`
  - then select target through Notion's `Window` menu
  - then use AX to raise / select the tab
- Result:
  - works for visible windows
  - works for minimized windows
  - works for inactive-Space windows in current user validation
- Remaining UX issues:
  - a different visible Notion window may get focus briefly before the real target window is restored
  - window activation feels slower than desired
  - tab activation feels slower than desired
  - the interaction can feel like a two-step jump instead of a direct target jump

Current activation direction:

- `app-first` is the leading candidate.
- `menu-only` remains useful as a baseline and fallback comparison path.

## Official Activation API Research

Reviewed Apple public activation APIs:

- `NSRunningApplication.activate(options:)`
- `NSRunningApplication.activate(from:options:)`
- `NSApplication.yieldActivation(to:)`
- `NSWindow.orderFrontRegardless()`

Findings:

- `NSRunningApplication.activate(options:)` is the primary public app-activation API.
- `activate(from:options:)` and `yieldActivation(to:)` are cooperative and depend on the target app's participation.
- `NSWindow.orderFrontRegardless()` is only applicable to a window owned by the app issuing the call.
- No public Apple API was identified that directly guarantees "bring this specific existing window of another app to the front, across an inactive Space" in one step.

Conclusion:

- The current `app-first` strategy is the best available public API path for activation.
- Further gains are likely to come from matching and state-handling improvements, not from a different official activation primitive.

## Activation Optimization Direction

The activation problem now appears split into two phases:

1. correctness
2. interaction quality

Correctness status:

- `app-first` is currently good enough to call the target window and tab across:
  - visible state
  - minimized state
  - inactive Space state

Remaining optimization targets:

- reduce time spent in fixed sleeps
- reduce intermediate focus jumps to the wrong Notion window
- determine whether `AXRaise` is redundant after `app-first + Window menu`
- measure window-only and tab-only costs separately

Current practical direction:

- keep `app-first` as the active product candidate
- optimize the current path before searching for a wholly different activation mechanism
