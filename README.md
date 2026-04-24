# notion-tabs-poc

PoC CLI for validating Notion desktop tab introspection and activation on macOS.

## Commands

```bash
swift run notion-tabs-poc status --prompt
swift run notion-tabs-poc list
swift run notion-tabs-poc persisted-list
swift run notion-tabs-poc persisted-watch --interval-ms 500
swift run notion-tabs-poc dump --depth 7
swift run notion-tabs-poc activate --window 1 --tab 2
swift run notion-tabs-poc activate-window-persisted --window 1 --pause-ms 700 --strategy menu-only
swift run notion-tabs-poc activate-window-persisted --window 1 --pause-ms 700 --strategy app-first
swift run notion-tabs-poc activate-persisted --window 1 --tab 4 --pause-ms 700 --strategy menu-only
swift run notion-tabs-poc activate-persisted --window 1 --tab 4 --pause-ms 700 --strategy app-first
swift run notion-tabs-poc probe --window 1
swift run notion-tabs-poc verify --window 1 --range 1-12 --pause-ms 350
swift run notion-tabs-poc verify-list --repeats 2 --pause-ms 500
swift run notion-tabs-poc window-sources
swift run notion-tabs-poc menu-tabs
```

## Notes

- Requires macOS Accessibility permission.
- Notion app must be running locally.
- This repository currently focuses on feasibility for window/tab extraction and activation.
- `persisted-list` reads Notion's passive `state.json` snapshot for full window/tab state.
- `persisted-watch` polls `state.json` and prints a new snapshot whenever the persisted window/tab state changes.
- `activate-window-persisted` tests window activation only, using persisted snapshot indices.
- `activate-persisted` tests window activation and then tab activation, using persisted snapshot indices.
- `--strategy menu-only` is the current baseline.
- `--strategy app-first` first asks macOS to activate Notion via `NSRunningApplication.activate(options: [.activateAllWindows])`, then selects the target from Notion's `Window` menu.
- Tab activation now tries `AXScrollToVisible` before `AXPress`, with a coordinate-click fallback when AX confirmation does not arrive.
- `--pause-ms` is now used as a per-step timeout budget for state-based polling rather than a fixed sleep between every step.
- `verify-list` traverses Notion's `Window` menu to validate per-window tab list reading when `AXWindows` only exposes the focused window.
- `window-sources` compares Accessibility, the `Window` menu, Quartz Window Services, and ScreenCaptureKit for cross-Space window discovery.
