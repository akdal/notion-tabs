import Foundation

struct FocusedWindowMatcher {
    private let frameTolerance: Double = 32

    func match(target: PersistedWindowRecord, focused: AXWindowRecord?) -> FocusedWindowBridgeRecord {
        guard let focused else {
            return FocusedWindowBridgeRecord(
                requestedWindowID: target.windowID,
                targetTitle: target.activeTitle,
                targetBounds: target.bounds,
                focusedWindow: nil,
                decision: "missing",
                reason: "no focused AX window",
                titleMatches: false,
                frameDistance: nil
            )
        }

        let titleMatches = normalized(target.activeTitle) == normalized(focused.title)
        let distance = focused.frame.map { frameDistance(target.bounds, $0) }
        let frameMatches = distance.map { $0 <= frameTolerance } ?? false

        let decision: String
        let reason: String
        if titleMatches && frameMatches {
            decision = "matched"
            reason = "title exact and frame within tolerance"
        } else if titleMatches && focused.frame == nil {
            decision = "matched"
            reason = "title exact; focused frame unavailable"
        } else if titleMatches {
            decision = "ambiguous"
            reason = "title exact but frame distance \(String(format: "%.0f", distance ?? -1)) exceeds tolerance \(Int(frameTolerance))"
        } else {
            decision = "missing"
            reason = "focused title '\(focused.title)' does not match target '\(target.activeTitle)'"
        }

        return FocusedWindowBridgeRecord(
            requestedWindowID: target.windowID,
            targetTitle: target.activeTitle,
            targetBounds: target.bounds,
            focusedWindow: focused,
            decision: decision,
            reason: reason,
            titleMatches: titleMatches,
            frameDistance: distance
        )
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func frameDistance(_ lhs: RectRecord, _ rhs: RectRecord) -> Double {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }
}

