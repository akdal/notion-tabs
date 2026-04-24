# Review Checkpoints

## Checkpoint 1: AX Access Baseline

When: after `status` + `dump` work end-to-end.

Review focus:

- Permission handling path is correct and explicit.
- Notion app discovery logic is robust enough (`bundleIdentifier` and fallback name matching).
- AX dump includes enough diagnostics (role/title/value/selected/actions).

Exit criteria:

- Team can inspect real Notion UI structure from dump output.

## Checkpoint 2: Tab Extraction Heuristics

When: after `list` shows window-grouped tabs.

Review focus:

- Candidate selection is not overfitting a single UI state.
- Ordering behavior matches Notion tab strip order.
- False positives are minimized for non-tab buttons.

Exit criteria:

- At least 3-5 repeated runs produce consistent per-window tab order.

## Checkpoint 3: Activation Reliability

When: after `activate` command works on multiple windows.

Review focus:

- Foreground behavior is predictable.
- Action fallback logic (`AXPress`, `AXPick`) is safe.
- Error reporting is actionable when activation fails.

Exit criteria:

- Activation succeeds repeatedly across different windows/tabs with no manual retries.

## Checkpoint 4: Productization Gate

When: before starting Menubar app shell.

Review focus:

- Decide what PoC code is production-ready.
- Separate diagnostics/debug code from runtime feature code.
- Confirm remaining unknowns for global hotkey and menu UX.

Exit criteria:

- Clear go/no-go decision for Menubar/Dock app implementation.
