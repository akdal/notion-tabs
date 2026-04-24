# Notion Tabs PoC Plan

## Product Goal

The target product is a background macOS app that:

- stays available without taking focus from the current app
- shows the user's currently open Notion tabs at any time
- activates the chosen Notion window and tab immediately when the user selects one

Implication for the PoC:

- Reading tab lists without foreground activation is a product requirement.
- Any validation flow that activates Notion windows is acceptable for diagnostics, but it does not by itself prove the final product interaction model.

## Discovery Layers

The most realistic architecture is likely hybrid:

- Process discovery: use `NSWorkspace` / `NSRunningApplication` to find the live Notion app instance.
- Window discovery: use Quartz Window Services and/or Notion's `Window` menu as the cross-Space source of open windows.
- Tab discovery: use Accessibility on the target Notion window when the window is actually exposed through the app's accessibility tree.

Current implication:

- `ps` can help confirm that Notion is running, but it is not a window source.
- `AXWindows` is useful but currently appears Space-limited in this environment.
- `Window` menu is currently the best observed source for the full open-window list.
- A final product may need to merge multiple data sources instead of relying on one API.

## Scope

This PoC validates only the technical viability of the first three requirements:

1. Discover a running Notion desktop app process.
2. Read open tabs grouped by Notion window and preserve visible order.
3. Activate a selected Notion tab from external code.

Out of scope for this PoC:

- Menubar UI
- Dock visibility option
- global hotkey UI
- persistent settings UI
- launch at login

## Approach

Use macOS Accessibility APIs (`AXUIElement`) as the primary integration path.

Reason:

- Notion desktop tabs are expected to be app-internal UI (likely Electron/Chromium rendered).
- Native `NSWindow` tab APIs are usually insufficient for external tab introspection in this shape.
- Accessibility tree inspection provides both discoverability (titles, ordering) and action execution (`AXPress`).

## Code Structure

Implemented in a Swift Package executable:

- `Sources/NotionTabsPOC/main.swift`
  - CLI commands:
    - `status [--prompt]`
    - `list`
    - `dump [--depth N]`
    - `activate --window N --tab M`
- `Core/`
  - `PermissionManager.swift`: accessibility trust check/prompt
  - `AppActivationService.swift`: foreground activation for Notion
  - `Logger.swift`
- `Accessibility/`
  - `AXElement.swift`: wrapper around `AXUIElement`
  - `AXTreeDumper.swift`: debug dump for tree inspection
- `Notion/`
  - `NotionAppLocator.swift`: Notion process discovery
  - `NotionWindowScanner.swift`: window grouping
  - `NotionTabScanner.swift`: tab-candidate extraction heuristics
  - `NotionTabActivator.swift`: tab action execution
  - `NotionModels.swift`: snapshots

## Validation Workflow

1. Permission and process check:

```bash
swift run notion-tabs-poc status --prompt
```

2. Window and tab extraction check:

```bash
swift run notion-tabs-poc list
```

3. AX tree structure sampling:

```bash
swift run notion-tabs-poc dump --depth 7
```

4. Activation check:

```bash
swift run notion-tabs-poc activate --window 1 --tab 2
```

## Success Criteria

- At least one Notion window is detected via Accessibility.
- Tab list appears per window with stable order matching visible UI.
- Activation command reliably focuses and switches to requested tab.

## Failure Signals

- No usable tab-like elements are exposed in the AX tree.
- Tab order cannot be reconstructed reliably from accessible children.
- Action calls (`AXPress`/`AXPick`) do not switch tabs consistently.
- Full multi-window tab discovery is only possible by activating windows/menu items first.

If these persist after scanner tuning, product scope should be reduced to window switching or page launcher behavior.
