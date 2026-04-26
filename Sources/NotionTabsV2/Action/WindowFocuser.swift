import AppKit
import ApplicationServices
import Foundation

enum FocusStrategy: String {
    case menuOnly = "menu-only"
    case appFirst = "app-first"
}

enum FocusTabStrategy: String {
    case pressOnly = "press-only"
    case scrollThenPress = "scroll-then-press"
    case coordinateClick = "coordinate-click"
}

struct WindowFocuser {
    func focus(
        app: NSRunningApplication,
        target: PersistedWindowRecord,
        menuItems: [MenuItemRecord],
        strategy: FocusStrategy,
        timeoutMS: Int
    ) -> FocusWindowActionRecord {
        let started = Date()
        let axApp = AXElementV2.application(pid: app.processIdentifier)
        let preFocused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
        var action: String?

        if strategy == .appFirst {
            _ = app.unhide()
            _ = app.activate(options: [.activateAllWindows])
        }

        let menuMatcher = MenuMatcher()
        let menuBridge = menuMatcher.match(persisted: [target], menuItems: menuItems).first
        guard
            menuBridge?.decision == "matched",
            let menuCandidate = menuBridge?.candidates.first,
            let menuElement = findMenuElement(appElement: axApp, menuIndex: menuCandidate.index)
        else {
            return FocusWindowActionRecord(
                requestedWindowID: target.windowID,
                strategy: strategy.rawValue,
                targetTitle: target.activeTitle,
                menuCandidate: menuBridge?.candidates.first,
                preFocusedWindow: preFocused,
                postFocusedWindow: AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier),
                action: nil,
                decision: menuBridge?.decision ?? "missing",
                reason: menuBridge?.reason ?? "menu target not found",
                elapsedMS: elapsed(started)
            )
        }

        action = performPressOrPick(menuElement)
        let postFocused = waitForFocusedWindow(pid: app.processIdentifier, target: target, timeoutMS: timeoutMS)
        let bridge = FocusedWindowMatcher().match(target: target, focused: postFocused)

        return FocusWindowActionRecord(
            requestedWindowID: target.windowID,
            strategy: strategy.rawValue,
            targetTitle: target.activeTitle,
            menuCandidate: menuCandidate,
            preFocusedWindow: preFocused,
            postFocusedWindow: postFocused,
            action: action,
            decision: bridge.decision,
            reason: bridge.reason,
            elapsedMS: elapsed(started)
        )
    }

    private func findMenuElement(appElement: AXElementV2, menuIndex: Int) -> AXElementV2? {
        guard
            let menuBar = appElement.children().first(where: { $0.role() == "AXMenuBar" }),
            let windowItem = menuBar.children().first(where: { $0.role() == "AXMenuBarItem" && $0.title() == "Window" }),
            let menu = windowItem.children().first(where: { $0.role() == "AXMenu" })
        else {
            return nil
        }
        let children = menu.children()
        guard children.indices.contains(menuIndex - 1) else { return nil }
        return children[menuIndex - 1]
    }

    private func performPressOrPick(_ element: AXElementV2) -> String? {
        let actions = element.actions()
        if actions.contains(kAXPressAction as String), element.perform(kAXPressAction as CFString) {
            return kAXPressAction as String
        }
        if actions.contains(kAXPickAction as String), element.perform(kAXPickAction as CFString) {
            return kAXPickAction as String
        }
        return nil
    }

    private func waitForFocusedWindow(pid: pid_t, target: PersistedWindowRecord, timeoutMS: Int) -> AXWindowRecord? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        while true {
            let focused = AXWindowInspector.focusedWindowRecord(pid: pid)
            let bridge = FocusedWindowMatcher().match(target: target, focused: focused)
            if bridge.decision == "matched" || Date() >= deadline {
                return focused
            }
            usleep(25_000)
        }
    }

    private func elapsed(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
