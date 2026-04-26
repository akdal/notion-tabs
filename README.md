# notion-tabs

Notion Desktop tab/window control CLI for macOS.

Current product entrypoint is `notion-tabs` (`NotionTabsCore` + CLI).

## Requirements

- macOS (tested on Apple Silicon)
- Notion Desktop app running (`bundle id: notion.id`)
- Accessibility permission granted to terminal app

## Build

```bash
swift build
```

## Product CLI

```bash
swift run notion-tabs list
swift run notion-tabs focus-window --window 2
swift run notion-tabs focus-tab --window 2 --tab 8
```

JSON mode (for UI/automation):

```bash
swift run notion-tabs list --json
swift run notion-tabs focus-window --window 1 --json
swift run notion-tabs focus-tab --window 2 --tab 8 --json
```

## Focus Strategy Chain

`focus-tab` executes in this order:

1. `command-number` (`Command + 1...9`, when tab index is in range)
2. `coordinate-click` (AX tab button candidate click)
3. `command-cycle` (`Command+Shift+] / Command+Shift+[`) based on persisted index distance

Final success is always validated by AX focused title.

## Error Contract

With `--json`, failures return structured error payload:

```json
{
  "success": false,
  "error": {
    "code": "WINDOW_NOT_FOUND",
    "message": "Window not found: 99"
  }
}
```

Known codes:

- `NOTION_NOT_RUNNING`
- `STATE_UNAVAILABLE`
- `WINDOW_NOT_FOUND`
- `TAB_NOT_FOUND`
- `WINDOW_MENU_UNAVAILABLE`
- `FOCUSED_WINDOW_UNAVAILABLE`
- `TAB_BUTTON_UNAVAILABLE`
- `ACTION_FAILED`
- `UNKNOWN_ERROR`

## Docs

- CLI contract: [docs/cli-contract.md](docs/cli-contract.md)
- Priority/status: [docs/todo-priority.md](docs/todo-priority.md)
- Shortcut modifier validation: [docs/validation-shortcut-modifier-20260426.md](docs/validation-shortcut-modifier-20260426.md)
- Next work plan (UI phase): [docs/next-work-plan.md](docs/next-work-plan.md)

## Legacy / Research Binaries

- `notion-tabs-poc`: legacy PoC commands
- `notion-tabs-v2`: validation/research runner

These remain for investigation and regression checks, but product integration should target `notion-tabs --json`.
