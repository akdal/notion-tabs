# Next Work Plan (Post-CLI Hardening)

Date: 2026-04-26

## Goal

- Build UI on top of stabilized `notion-tabs` core/CLI contract.
- Keep verification closed-loop (CLI JSON output + AX truth).

## Scope

1. UI shell + IPC
- Create minimal macOS UI shell for:
  - window/tab list read
  - tab/window focus action
- Invoke CLI with `--json` only.
- Parse and surface:
  - `success`
  - `strategy`
  - `targetTitle`
  - `focusedTitle`
  - `error.code`, `error.message`

2. UI state model
- Normalize list payload into local view model:
  - windows
  - tabs
  - `isAXFocused`
  - `isPersistedActive`
- Add refresh policy:
  - manual refresh
  - optional interval refresh

3. Action flow
- `focus-tab` action:
  - optimistic pending state
  - completion state from CLI JSON
  - error banner/toast with `error.code`
- `focus-window` action:
  - same success/error pipeline

4. Verification hooks
- Add debug panel in UI:
  - raw CLI JSON response
  - elapsed ms
  - selected strategy
- Keep reproducible script for closed validation scenarios.

5. Packaging and runtime checks
- Validate accessibility permission guidance in UI.
- Add startup checks:
  - Notion running
  - state path readable

## Non-Goals (for next step)

- No new focus strategy beyond current chain.
- No refactor of legacy POC/V2 modules.

## Definition of Done

- UI can fully operate through `notion-tabs --json` contract.
- Closed verification scenarios pass from UI-triggered actions.
- Failures are user-visible with structured error codes.
