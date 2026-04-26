import ApplicationServices
import Foundation

struct AXWindowSource {
    func read(pid: pid_t) -> [AXWindowRecord] {
        let app = AXElementV2.application(pid: pid)
        var candidates = app.windows()
        if let focused = app.focusedWindow() {
            candidates.append(focused)
        }
        if candidates.isEmpty {
            candidates = app.descendants(role: "AXWindow", maxDepth: 16)
        }

        var records: [AXWindowRecord] = []
        for element in candidates {
            let title = element.title()
            let frame = element.frame().map(RectRecord.init)
            let key = "\(title)|\(frame?.x ?? -1)|\(frame?.y ?? -1)|\(frame?.width ?? -1)|\(frame?.height ?? -1)"
            if records.contains(where: { "\($0.title)|\($0.frame?.x ?? -1)|\($0.frame?.y ?? -1)|\($0.frame?.width ?? -1)|\($0.frame?.height ?? -1)" == key }) {
                continue
            }
            records.append(AXWindowRecord(
                index: records.count + 1,
                title: title,
                role: element.role(),
                frame: frame,
                isFocused: element.bool(kAXFocusedAttribute as CFString),
                isMain: element.bool(kAXMainAttribute as CFString),
                isMinimized: element.bool(kAXMinimizedAttribute as CFString),
                actions: element.actions()
            ))
        }
        return records
    }
}

struct WindowMenuSource {
    private let systemTitles = Set([
        "Minimize", "Minimize All", "Zoom", "Zoom All", "Fill", "Center",
        "Move & Resize", "Full Screen Tile", "Remove Window from Set",
        "Show Previous Tab", "Show Next Tab", "Bring All to Front", "Arrange in Front"
    ])

    func read(pid: pid_t) -> [MenuItemRecord] {
        let app = AXElementV2.application(pid: pid)
        guard
            let menuBar = app.children().first(where: { $0.role() == "AXMenuBar" }),
            let windowItem = menuBar.children().first(where: { $0.role() == "AXMenuBarItem" && $0.title() == "Window" }),
            let menu = windowItem.children().first(where: { $0.role() == "AXMenu" })
        else {
            return []
        }

        return menu.children().enumerated().map { offset, item in
            let title = item.title()
            return MenuItemRecord(
                index: offset + 1,
                title: title,
                role: item.role(),
                category: category(title: title),
                selected: item.isSelected(),
                actions: item.actions()
            )
        }
    }

    private func category(title: String) -> String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "separator"
        }
        if systemTitles.contains(title) {
            return "system"
        }
        return "document_candidate"
    }
}

struct FocusedTabsSource {
    private let topStripHeight: CGFloat = 120
    private let minTabHeight: CGFloat = 28
    private let maxTabHeight: CGFloat = 90
    private let minTabWidth: CGFloat = 90

    func read(pid: pid_t, strict: Bool) -> [FocusedTabRecord] {
        guard let focusedWindow = AXElementV2.application(pid: pid).focusedWindow() else {
            return []
        }
        let windowFrame = focusedWindow.frame()
        let candidates = collectCandidates(in: focusedWindow, windowFrame: windowFrame)
        let filtered = strict ? filterTopStripCluster(candidates, windowFrame: windowFrame) : candidates
        return filtered.enumerated().compactMap { offset, element in
            let title = normalizedLabel(element)
            guard !title.isEmpty else { return nil }
            return FocusedTabRecord(
                index: offset + 1,
                title: title,
                role: element.role(),
                value: element.valueString(),
                frame: element.frame().map(RectRecord.init),
                selected: element.isSelected(),
                actions: element.actions()
            )
        }
    }

    func readWebAreas(pid: pid_t) -> [FocusedTabRecord] {
        guard let focusedWindow = AXElementV2.application(pid: pid).focusedWindow() else {
            return []
        }
        let elements = focusedWindow.descendants(role: "AXWebArea", maxDepth: 14)
            .filter { !$0.title().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return dedupe(elements).enumerated().map { offset, element in
            FocusedTabRecord(
                index: offset + 1,
                title: element.title().trimmingCharacters(in: .whitespacesAndNewlines),
                role: element.role(),
                value: element.valueString(),
                frame: element.frame().map(RectRecord.init),
                selected: element.isSelected(),
                actions: element.actions()
            )
        }
    }

    private func collectCandidates(in window: AXElementV2, windowFrame: CGRect?) -> [AXElementV2] {
        var queue = [window]
        var candidates: [AXElementV2] = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in current.children() {
                let role = child.role()
                if
                    (role == "AXButton" || role == "AXTab" || role == "AXTabButton"),
                    !normalizedLabel(child).isEmpty,
                    isNearTop(child, windowFrame: windowFrame),
                    looksLikeTab(child)
                {
                    candidates.append(child)
                }
                queue.append(child)
            }
        }
        return dedupe(candidates)
    }

    private func isNearTop(_ element: AXElementV2, windowFrame: CGRect?) -> Bool {
        guard let frame = element.frame(), let windowFrame else { return false }
        return frame.minY - windowFrame.minY <= topStripHeight
    }

    private func looksLikeTab(_ element: AXElementV2) -> Bool {
        guard let frame = element.frame() else { return false }
        if frame.height < minTabHeight || frame.height > maxTabHeight { return false }
        if frame.width < minTabWidth { return false }
        return element.actions().contains("AXPress")
    }

    private func filterTopStripCluster(_ candidates: [AXElementV2], windowFrame: CGRect?) -> [AXElementV2] {
        guard let windowFrame else { return [] }
        let inBand = candidates.filter { element in
            guard let frame = element.frame() else { return false }
            return frame.minY - windowFrame.minY <= topStripHeight
        }
        let buckets = Dictionary(grouping: inBand) { element -> Int in
            Int(((element.frame()?.minY ?? -1) / 8).rounded())
        }
        let best = buckets.max { $0.value.count < $1.value.count }?.value ?? inBand
        return best.sorted { ($0.frame()?.minX ?? .greatestFiniteMagnitude) < ($1.frame()?.minX ?? .greatestFiniteMagnitude) }
    }

    private func normalizedLabel(_ element: AXElementV2) -> String {
        let title = element.title().trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return element.valueString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func dedupe(_ candidates: [AXElementV2]) -> [AXElementV2] {
        var seen: Set<String> = []
        var result: [AXElementV2] = []
        for element in candidates {
            let frame = element.frame() ?? .zero
            let key = "\(normalizedLabel(element))|\(Int(frame.minX))|\(Int(frame.minY))|\(Int(frame.width))|\(Int(frame.height))"
            if seen.insert(key).inserted {
                result.append(element)
            }
        }
        return result
    }
}
