import Foundation

struct NotionWindowScanner {
    private let tabScanner = NotionTabScanner()

    func scanWindows(appElement: AXElement) -> [NotionWindowSnapshot] {
        let windows = collectWindows(appElement: appElement)

        return windows.enumerated().map { index, window in
            let tabs = tabScanner.scanTabs(in: window)
            let title = window.title() ?? "Window \(index + 1)"
            return NotionWindowSnapshot(
                index: index + 1,
                title: title.isEmpty ? "Window \(index + 1)" : title,
                rawElement: window,
                tabs: tabs
            )
        }
    }

    private func collectWindows(appElement: AXElement) -> [AXElement] {
        var candidates = appElement.windows()
        if let focused = appElement.focusedWindow() {
            candidates.append(focused)
        }
        if candidates.isEmpty {
            candidates = appElement.descendantElements(role: "AXWindow", maxDepth: 16)
        }

        var unique: [AXElement] = []
        for element in candidates {
            if unique.contains(where: { $0.isEqualTo(element) }) { continue }
            unique.append(element)
        }
        return unique
    }
}
