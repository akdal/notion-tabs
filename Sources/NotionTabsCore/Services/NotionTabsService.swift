import ApplicationServices
import AppKit
import Foundation

public final class NotionTabsService {
    private let process = NotionProcess()
    private let stateStore = NotionStateStore()
    private let focusedReader = FocusedWindowReader()
    private let windowMenu = WindowMenuReader()
    private let tabStrip = TabStripReader()
    private let commandShortcut = CommandNumberShortcutFocuser()
    private let tabCycler = CommandTabCycler()
    private let clicker = CoordinateClicker()

    public init() {}

    public func listWindows() throws -> ListSnapshot {
        let app = try process.runningApp()
        let state = try stateStore.read()
        let focusedTitle = focusedReader.focusedTitle(pid: app.processIdentifier)
        let menuTitles = Set((try? windowMenu.read(pid: app.processIdentifier).map { normalize($0.title) }) ?? [])

        let windows = state.windows.map { window in
            let tabs = window.tabs.map { tab in
                TabSnapshot(
                    id: tab.id,
                    index: tab.index,
                    title: tab.title,
                    isPersistedActive: normalize(tab.title) == normalize(window.activeTitle),
                    isAXFocused: normalize(tab.title) == normalize(focusedTitle ?? "")
                )
            }
            return WindowSnapshot(
                id: window.id,
                index: window.index,
                persistedActiveTitle: window.activeTitle,
                frame: RectSnapshot(window.frame),
                isAXFocused: normalize(window.activeTitle) == normalize(focusedTitle ?? ""),
                isInWindowMenu: menuTitles.contains(normalize(window.activeTitle)),
                tabs: tabs
            )
        }

        return ListSnapshot(
            focusedTitle: focusedTitle,
            statePath: state.path,
            stateModifiedAt: state.modifiedAt,
            windows: windows
        )
    }

    public func focusWindow(_ ref: WindowRef, timeoutMS: Int = 2_000) throws -> FocusResult {
        let app = try process.runningApp()
        let state = try stateStore.read()
        let target = try resolveWindow(ref, in: state)
        return try focusWindow(target, app: app, timeoutMS: timeoutMS)
    }

    private func focusWindow(_ target: PersistedWindow, app: NSRunningApplication, timeoutMS: Int) throws -> FocusResult {
        let items = try windowMenu.read(pid: app.processIdentifier)
        guard let item = windowMenuItem(for: target, items: items) else {
            throw NotionTabsError.windowNotFound(target.activeTitle)
        }

        let pressed = item.element.perform(kAXPressAction as CFString) || item.element.perform(kAXPickAction as CFString)
        guard pressed else {
            throw NotionTabsError.actionFailed("Failed to press Window menu item: \(target.activeTitle)")
        }

        let focusedTitle = waitForFocusedTitle(pid: app.processIdentifier, title: target.activeTitle, timeoutMS: timeoutMS)
        let success = normalize(focusedTitle ?? "") == normalize(target.activeTitle)
        return FocusResult(
            success: success,
            targetTitle: target.activeTitle,
            focusedTitle: focusedTitle,
            strategy: "window-menu",
            message: success ? "focused window: \(target.activeTitle)" : "window menu pressed, but focus verification failed"
        )
    }

    public func focusTab(window windowRef: WindowRef, tab tabRef: TabRef, timeoutMS: Int = 2_500) throws -> FocusResult {
        let app = try process.runningApp()
        let state = try stateStore.read()
        let targetWindow = try resolveWindow(windowRef, in: state)
        let targetTab = try resolveTab(tabRef, in: targetWindow)

        if !focusedWindowContainsAllTabs(pid: app.processIdentifier, targetWindow: targetWindow) {
            _ = try focusWindow(targetWindow, app: app, timeoutMS: max(1_000, timeoutMS))
        }

        guard let focusedWindow = focusedReader.focusedWindow(pid: app.processIdentifier) else {
            throw NotionTabsError.focusedWindowUnavailable
        }

        if (1...9).contains(targetTab.index) {
            let posted = commandShortcut.press(tabIndex: targetTab.index, app: app)
            if posted {
                let shortcutFocusedTitle = waitForFocusedTitle(
                    pid: app.processIdentifier,
                    title: targetTab.title,
                    timeoutMS: min(timeoutMS, 1_000)
                )
                if normalize(shortcutFocusedTitle ?? "") == normalize(targetTab.title) {
                    return FocusResult(
                        success: true,
                        targetTitle: targetTab.title,
                        focusedTitle: shortcutFocusedTitle,
                        strategy: "command-number",
                        message: "focused tab: \(targetTab.title) (strategy=command-number)"
                    )
                }
            }
        }

        if let candidate = tabStrip.preferredButton(in: focusedWindow, title: targetTab.title) {
            clicker.click(candidate: candidate, app: app, window: focusedWindow)
            let focusedTitle = waitForFocusedTitle(pid: app.processIdentifier, title: targetTab.title, timeoutMS: timeoutMS)
            let success = normalize(focusedTitle ?? "") == normalize(targetTab.title)
            if success {
                return FocusResult(
                    success: true,
                    targetTitle: targetTab.title,
                    focusedTitle: focusedTitle,
                    strategy: "coordinate-click",
                    message: "focused tab: \(targetTab.title) (strategy=coordinate-click)"
                )
            }
        }

        if let cycled = cycleToTabByCommandCycle(targetWindow: targetWindow, targetTab: targetTab, app: app, timeoutMS: timeoutMS) {
            return cycled
        }

        throw NotionTabsError.tabButtonUnavailable(targetTab.title)
    }

    private func resolveWindow(_ ref: WindowRef, in state: PersistedState) throws -> PersistedWindow {
        if let index = Int(ref.value), let window = state.windows.first(where: { $0.index == index }) {
            return window
        }
        if let window = state.windows.first(where: { $0.id == ref.value || $0.id.hasPrefix(ref.value) }) {
            return window
        }
        throw NotionTabsError.windowNotFound(ref.value)
    }

    private func resolveTab(_ ref: TabRef, in window: PersistedWindow) throws -> PersistedTab {
        if let index = Int(ref.value), let tab = window.tabs.first(where: { $0.index == index }) {
            return tab
        }
        if let tab = window.tabs.first(where: { $0.id == ref.value || $0.id.hasPrefix(ref.value) }) {
            return tab
        }
        if let tab = window.tabs.first(where: { normalize($0.title) == normalize(ref.value) }) {
            return tab
        }
        throw NotionTabsError.tabNotFound(ref.value)
    }

    private func windowMenuItem(for target: PersistedWindow, items: [WindowMenuItem]) -> WindowMenuItem? {
        if let item = items.first(where: { normalize($0.title) == normalize(target.activeTitle) }) {
            return item
        }

        let tabTitles = Set(target.tabs.map { normalize($0.title) })
        let candidates = items.filter { tabTitles.contains(normalize($0.title)) }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func focusedWindowContainsAllTabs(pid: pid_t, targetWindow: PersistedWindow) -> Bool {
        guard let focusedWindow = focusedReader.focusedWindow(pid: pid) else {
            return false
        }
        let observedTitles = tabStrip.observedTabTitles(in: focusedWindow)
        return targetWindow.tabs.allSatisfy { observedTitles.contains(normalize($0.title)) }
    }

    private func cycleToTabByCommandCycle(
        targetWindow: PersistedWindow,
        targetTab: PersistedTab,
        app: NSRunningApplication,
        timeoutMS: Int
    ) -> FocusResult? {
        guard
            let currentTitle = focusedReader.focusedTitle(pid: app.processIdentifier),
            let current = targetWindow.tabs.first(where: { normalize($0.title) == normalize(currentTitle) })
        else {
            return nil
        }

        if current.index == targetTab.index {
            return FocusResult(
                success: true,
                targetTitle: targetTab.title,
                focusedTitle: currentTitle,
                strategy: "already-focused",
                message: "focused tab: \(targetTab.title) (strategy=already-focused)"
            )
        }

        let total = max(1, targetWindow.tabs.count)
        let forward = (targetTab.index - current.index + total) % total
        let backward = (current.index - targetTab.index + total) % total
        let useForward = forward <= backward
        let steps = useForward ? forward : backward
        guard steps > 0 else { return nil }
        guard tabCycler.cycle(forward: useForward, steps: steps, app: app) else { return nil }

        let focusedTitle = waitForFocusedTitle(pid: app.processIdentifier, title: targetTab.title, timeoutMS: timeoutMS)
        let success = normalize(focusedTitle ?? "") == normalize(targetTab.title)
        return success ? FocusResult(
            success: true,
            targetTitle: targetTab.title,
            focusedTitle: focusedTitle,
            strategy: "command-cycle",
            message: "focused tab: \(targetTab.title) (strategy=command-cycle)"
        ) : nil
    }

    private func waitForFocusedTitle(pid: pid_t, title: String, timeoutMS: Int) -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        var latest: String?
        while true {
            latest = focusedReader.focusedTitle(pid: pid)
            if normalize(latest ?? "") == normalize(title) || Date() >= deadline {
                return latest
            }
            usleep(50_000)
        }
    }
}
