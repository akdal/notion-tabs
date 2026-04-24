import Foundation

struct NotionTabScanner {
    private let topStripHeight: CGFloat = 120
    private let minTabHeight: CGFloat = 28
    private let maxTabHeight: CGFloat = 90
    private let minTabWidth: CGFloat = 90

    func scanTabs(in window: AXElement, strict: Bool = true) -> [NotionTabSnapshot] {
        let windowFrame = window.frame()
        let candidates = collectButtonCandidates(in: window, windowFrame: windowFrame)
        if strict {
            return toSnapshots(filterTopStripCluster(candidates, windowFrame: windowFrame))
        }
        return toSnapshots(candidates)
    }

    private func collectButtonCandidates(in window: AXElement, windowFrame: CGRect?) -> [AXElement] {
        var queue: [AXElement] = [window]
        var candidates: [AXElement] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for child in current.children() {
                if
                    (child.role() == "AXButton" || child.role() == "AXTab" || child.role() == "AXTabButton"),
                    normalizedLabel(for: child) != nil,
                    isNearWindowTop(child: child, windowFrame: windowFrame),
                    looksLikeTabButton(child: child)
                {
                    candidates.append(child)
                }
                queue.append(child)
            }
        }

        return dedupeByGeometryAndTitle(candidates)
    }

    private func isNearWindowTop(child: AXElement, windowFrame: CGRect?) -> Bool {
        guard let frame = child.frame(), let windowFrame else { return false }
        return frame.minY - windowFrame.minY <= topStripHeight
    }

    private func looksLikeTabButton(child: AXElement) -> Bool {
        guard let frame = child.frame() else { return false }
        if frame.height < minTabHeight || frame.height > maxTabHeight { return false }
        if frame.width < minTabWidth { return false }
        let actions = Set(child.actionNames())
        guard actions.contains("AXPress") else { return false }
        if actions.contains("AXShowMenu") && actions.contains("AXScrollToVisible") {
            return true
        }
        return actions.count == 1
    }

    private func filterTopStripCluster(_ candidates: [AXElement], windowFrame: CGRect?) -> [AXElement] {
        guard !candidates.isEmpty else { return [] }
        guard let windowFrame else { return [] }

        let inBand = candidates.filter { element in
            guard let frame = element.frame() else { return false }
            return frame.minY - windowFrame.minY <= topStripHeight
        }
        guard !inBand.isEmpty else { return [] }

        let yBuckets = Dictionary(grouping: inBand) { element -> Int in
            guard let y = element.frame()?.minY else { return -1 }
            return Int((y / 8).rounded())
        }
        let bestBucket = yBuckets.max { lhs, rhs in lhs.value.count < rhs.value.count }?.value ?? inBand
        let sorted = bestBucket.sorted { lhs, rhs in
            (lhs.frame()?.minX ?? .greatestFiniteMagnitude) < (rhs.frame()?.minX ?? .greatestFiniteMagnitude)
        }
        return sorted
    }

    private func dedupeByGeometryAndTitle(_ candidates: [AXElement]) -> [AXElement] {
        var seen: Set<String> = []
        var result: [AXElement] = []
        for element in candidates {
            let title = normalizedLabel(for: element) ?? ""
            let frame = element.frame() ?? .zero
            let key = "\(title)|\(Int(frame.minX))|\(Int(frame.minY))|\(Int(frame.width))|\(Int(frame.height))"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(element)
        }
        return result
    }

    private func normalizedLabel(for element: AXElement) -> String? {
        let title = element.title()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return title
        }
        let value = element.valueString()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    private func toSnapshots(_ elements: [AXElement]) -> [NotionTabSnapshot] {
        elements.enumerated().compactMap { idx, element in
            guard let label = normalizedLabel(for: element), !label.isEmpty else { return nil }
            return NotionTabSnapshot(
                index: idx + 1,
                title: label,
                isSelected: element.isSelected() ?? false,
                rawElement: element
            )
        }
    }
}
