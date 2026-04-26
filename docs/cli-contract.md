# CLI Contract (`notion-tabs`)

## Commands

- `notion-tabs list [--json]`
- `notion-tabs focus-window --window <index|id-prefix> [--json]`
- `notion-tabs focus-tab --window <index|id-prefix> --tab <index|id-prefix|exact-title> [--json]`

## JSON Output

`--json` is supported for all commands.

### Success: `list --json`

- `success: true`
- `focusedTitle: string | null`
- `state.path: string`
- `state.modifiedAt: string(ISO8601) | null`
- `windows[]`
  - `id: string`
  - `index: number`
  - `persistedActiveTitle: string`
  - `isAXFocused: boolean`
  - `isInWindowMenu: boolean`
  - `frame: { x, y, width, height }`
  - `tabs[]: { id, index, title, isPersistedActive, isAXFocused }`

### Success: `focus-window|focus-tab --json`

- `success: boolean`
- `targetTitle: string`
- `focusedTitle: string | null`
- `strategy: string | null`
- `message: string`

Known `strategy` values:

- `window-menu`
- `command-number`
- `coordinate-click`
- `command-cycle`
- `already-focused`

### Error: any command with `--json`

- `success: false`
- `error.code: string`
- `error.message: string`

Known error codes:

- `NOTION_NOT_RUNNING`
- `STATE_UNAVAILABLE`
- `WINDOW_NOT_FOUND`
- `TAB_NOT_FOUND`
- `WINDOW_MENU_UNAVAILABLE`
- `FOCUSED_WINDOW_UNAVAILABLE`
- `TAB_BUTTON_UNAVAILABLE`
- `ACTION_FAILED`
- `UNKNOWN_ERROR`
