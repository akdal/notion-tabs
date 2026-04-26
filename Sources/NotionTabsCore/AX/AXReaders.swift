import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct NotionProcess {
    func runningApp() throws -> NSRunningApplication {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "notion.id")
        guard let app = apps.first else {
            throw NotionTabsError.notionNotRunning
        }
        return app
    }
}

struct WindowMenuItem {
    let index: Int
    let title: String
    let element: AXElement
}

struct WindowMenuReader {
    private let systemTitles = Set([
        "Minimize", "Minimize All", "Zoom", "Zoom All", "Fill", "Center",
        "Move & Resize", "Full Screen Tile", "Remove Window from Set",
        "Show Previous Tab", "Show Next Tab", "Bring All to Front", "Arrange in Front"
    ])

    func read(pid: pid_t) throws -> [WindowMenuItem] {
        try readAll(pid: pid).filter { !systemTitles.contains($0.title) }
    }

    func readAll(pid: pid_t) throws -> [WindowMenuItem] {
        let app = AXElement.application(pid: pid)
        guard
            let menuBar = app.children().first(where: { $0.role() == "AXMenuBar" }),
            let windowItem = menuBar.children().first(where: { $0.role() == "AXMenuBarItem" && $0.title() == "Window" }),
            let menu = windowItem.children().first(where: { $0.role() == "AXMenu" })
        else {
            throw NotionTabsError.windowMenuUnavailable
        }

        return menu.children().enumerated().compactMap { offset, item in
            let title = item.title().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return WindowMenuItem(index: offset + 1, title: title, element: item)
        }
    }
}

struct FocusedWindowReader {
    func focusedWindow(pid: pid_t) -> AXElement? {
        AXElement.application(pid: pid).focusedWindow()
    }

    func focusedTitle(pid: pid_t) -> String? {
        focusedWindow(pid: pid)?.title().nilIfEmpty
    }
}

struct TabButtonCandidate {
    let title: String
    let frame: CGRect
    let element: AXElement
}

struct TabStripReader {
    func preferredButton(in window: AXElement, title: String) -> TabButtonCandidate? {
        let windowFrame = window.frame()
        var matches: [TabButtonCandidate] = []
        walk(root: window, maxDepth: 18) { element, depth in
            guard depth > 0 else { return }
            guard element.role() == "AXButton" else { return }
            guard normalize(element.title()) == normalize(title) else { return }
            guard element.actions().contains(kAXPressAction as String) else { return }
            guard let frame = element.frame(), isInTabStrip(frame: frame, windowFrame: windowFrame) else { return }
            matches.append(TabButtonCandidate(title: element.title(), frame: frame, element: element))
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func observedTabTitles(in window: AXElement) -> Set<String> {
        let windowFrame = window.frame()
        var titles: Set<String> = []
        walk(root: window, maxDepth: 18) { element, depth in
            guard depth > 0 else { return }
            guard element.role() == "AXButton" else { return }
            guard element.actions().contains(kAXPressAction as String) else { return }
            guard let frame = element.frame(), isInTabStrip(frame: frame, windowFrame: windowFrame) else { return }
            let title = element.title().trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                titles.insert(normalize(title))
            }
        }
        return titles
    }

    private func isInTabStrip(frame: CGRect, windowFrame: CGRect?) -> Bool {
        guard let windowFrame else { return false }
        return frame.minY - windowFrame.minY <= 44
    }

    private func walk(root: AXElement, maxDepth: Int, visit: (AXElement, Int) -> Void) {
        var queue: [(AXElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visit(element, depth)
            if depth >= maxDepth { continue }
            for child in element.children() {
                queue.append((child, depth + 1))
            }
        }
    }
}

struct CoordinateClicker {
    func click(candidate: TabButtonCandidate, app: NSRunningApplication, window: AXElement) {
        _ = app.activate(options: [.activateIgnoringOtherApps])
        _ = window.perform("AXRaise" as CFString)
        usleep(500_000)

        let point = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
        let moved = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        moved?.post(tap: .cghidEventTap)
        usleep(20_000)
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
    }
}

struct CommandNumberShortcutFocuser {
    func press(tabIndex: Int, app: NSRunningApplication) -> Bool {
        guard let keyCode = keyCodeForTabIndex(tabIndex) else { return false }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        usleep(120_000)

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        usleep(20_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func keyCodeForTabIndex(_ tabIndex: Int) -> CGKeyCode? {
        switch tabIndex {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        default: return nil
        }
    }
}

struct CommandTabCycler {
    func cycle(forward: Bool, steps: Int, app: NSRunningApplication) -> Bool {
        guard steps > 0 else { return true }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        usleep(120_000)
        for _ in 0 ..< steps {
            if !postCycleEvent(forward: forward) {
                return false
            }
            usleep(120_000)
        }
        return true
    }

    private func postCycleEvent(forward: Bool) -> Bool {
        let keyCode: CGKeyCode = forward ? 30 : 33
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }
        keyDown.flags = [.maskCommand, .maskShift]
        keyUp.flags = [.maskCommand, .maskShift]
        keyDown.post(tap: .cghidEventTap)
        usleep(20_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
