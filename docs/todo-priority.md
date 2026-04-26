# Priority TODO (Locked Order)

This order is fixed and must be followed.

## 1) CLI/Core parity with final POC (first, mandatory)

Goal:

- `notion-tabs` (product CLI + `NotionTabsCore`) must behave the same as the validated final POC path (`notion-tabs-v2`) for the supported commands.

Scope:

- `list`
- `focus-window`
- `focus-tab`

Parity checks:

1. Same input references are accepted (index / id prefix / title where supported).
2. Same success/failure behavior for common scenarios:
   - same-window tab switch
   - cross-window tab switch
   - window not focused before tab switch
   - stale `state.json` active title cases
3. Same practical outcome:
   - post action focused title matches expected target (AX truth).
4. No regression in user UX:
   - `focus-window --window X --tab Y` must route to tab focus behavior.

Definition of done:

- The above scenarios pass with `notion-tabs` using only product Core code.
- Results are documented and reproducible.

Current status:

- Closed.
- Closed verification (AX focused title oracle via `notion-tabs-v2 source focused-window`) passed for:
  - Window 1 tab 2 -> `@Last Monday VS Daily Stand-up`
  - Window 1 tab 5 -> `Points 기획`
  - Window 2 tab 1 -> `Privy 다중 계정 연동 기획`
  - Window 3 tab 1 -> `알로콘`
  - Window 1 tab 3 -> `Versus 수집 이벤트`
- Fixed during parity:
  - `focus-window --window X --tab Y` now routes to tab focus.
  - `focusTab` no longer depends on stale `state.json` active title for repeated same-window transitions.
  - If focused AX tree already matches target window tabs, refocus is skipped.

## 2) Add tab focus strategy chain (after parity is done)

Feature:

- Primary attempt: macOS `Command + number` for tab index `1...9`.
- Secondary attempt (fallback): existing coordinate click strategy.

Constraints:

- Only start this after section 1 is complete.
- Keep the same post-action verification rule (AX focused title).

Current status:

- Closed.
- Implemented in product core:
  - Primary attempt: `Command + number` for tab index `1...9`.
  - Secondary fallback: coordinate click on matched tab button.
  - Tertiary fallback: `Command+Shift+] / Command+Shift+[` cycle based on persisted tab index distance.
- Corrected:
  - Modifier fixed from `Control` to `Command` (validated in `docs/validation-shortcut-modifier-20260426.md`).
  - Removed hard precondition that blocked actions when focused AX tree did not expose all persisted tabs.
- Closed checks observed both paths:
  - `strategy=command-number`: Window 1 tab 3, Window 2 tab 8.
  - `strategy=coordinate-click`: Window 3 tab 2.
  - `strategy=command-cycle`: Window 1 tab 12.
  - All above matched AX focused title oracle (`notion-tabs-v2 source focused-window`).

## Notes

- `state.json` remains inventory, not realtime active truth.
- AX focused title remains immediate active truth.
