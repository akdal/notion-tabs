import Foundation

struct WindowMatcher {
    private let highConfidenceScore = 40
    private let ambiguousGap = 15

    func match(persisted: [PersistedWindowRecord], live: [LiveWindowRecord]) -> [WindowBridgeRecord] {
        persisted.map { window in
            let candidates = mergedLiveWindows(live).map { candidate(window: window, live: $0) }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score < rhs.score }
                    return lhs.source < rhs.source
                }
            return decide(window: window, candidates: candidates)
        }
    }

    private func mergedLiveWindows(_ windows: [LiveWindowRecord]) -> [LiveWindowRecord] {
        let grouped = Dictionary(grouping: windows) { window in
            [
                normalized(window.title ?? ""),
                String(Int(window.frame.x.rounded())),
                String(Int(window.frame.y.rounded())),
                String(Int(window.frame.width.rounded())),
                String(Int(window.frame.height.rounded()))
            ].joined(separator: "|")
        }

        return grouped.values.map { group in
            let sorted = group.sorted { $0.source < $1.source }
            let first = sorted[0]
            return LiveWindowRecord(
                source: sorted.map(\.source).joined(separator: "+"),
                index: first.index,
                windowID: sorted.compactMap(\.windowID).joined(separator: "+"),
                title: first.title,
                frame: first.frame,
                isOnScreen: sorted.compactMap(\.isOnScreen).first,
                isActive: sorted.compactMap(\.isActive).first,
                layer: sorted.compactMap(\.layer).first,
                alpha: sorted.compactMap(\.alpha).first
            )
        }
    }

    private func candidate(window: PersistedWindowRecord, live: LiveWindowRecord) -> WindowMatchCandidate {
        let title = live.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleDecision: String
        let titlePenalty: Int
        if let title, !title.isEmpty {
            if normalized(title) == normalized(window.activeTitle) {
                titleDecision = "exact"
                titlePenalty = 0
            } else {
                titleDecision = "mismatch"
                titlePenalty = 100
            }
        } else {
            titleDecision = "missing"
            titlePenalty = 35
        }

        let distance = frameDistance(window.bounds, live.frame)
        let framePenalty = min(200, Int(distance))
        let score = titlePenalty + framePenalty
        let reason = "title=\(titleDecision),frameDistance=\(String(format: "%.0f", distance))"

        return WindowMatchCandidate(
            source: live.source,
            index: live.index,
            windowID: live.windowID,
            title: live.title,
            frame: live.frame,
            score: score,
            titleDecision: titleDecision,
            frameDistance: distance,
            reason: reason
        )
    }

    private func decide(window: PersistedWindowRecord, candidates: [WindowMatchCandidate]) -> WindowBridgeRecord {
        guard let best = candidates.first else {
            return WindowBridgeRecord(
                persistedWindow: window,
                candidates: [],
                decision: "missing",
                reason: "no live window candidates"
            )
        }

        if best.score > highConfidenceScore {
            return WindowBridgeRecord(
                persistedWindow: window,
                candidates: Array(candidates.prefix(5)),
                decision: "missing",
                reason: "best score \(best.score) exceeds high confidence threshold \(highConfidenceScore)"
            )
        }

        if candidates.count >= 2 {
            let second = candidates[1]
            if second.score - best.score <= ambiguousGap {
                return WindowBridgeRecord(
                    persistedWindow: window,
                    candidates: Array(candidates.prefix(5)),
                    decision: "ambiguous",
                    reason: "top scores too close: best=\(best.score), second=\(second.score)"
                )
            }
        }

        return WindowBridgeRecord(
            persistedWindow: window,
            candidates: Array(candidates.prefix(5)),
            decision: "matched",
            reason: "one high-confidence candidate"
        )
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func frameDistance(_ lhs: RectRecord, _ rhs: RectRecord) -> Double {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }
}
