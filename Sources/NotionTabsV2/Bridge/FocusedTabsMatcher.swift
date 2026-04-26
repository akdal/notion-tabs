import Foundation

struct FocusedTabsMatcher {
    func match(
        targetWindow: PersistedWindowRecord,
        focusedWindowBridge: FocusedWindowBridgeRecord,
        axTabs: [FocusedTabRecord]
    ) -> FocusedTabsBridgeRecord {
        guard focusedWindowBridge.decision == "matched" else {
            return FocusedTabsBridgeRecord(
                requestedWindowID: targetWindow.windowID,
                targetWindowTitle: targetWindow.activeTitle,
                focusedWindowBridge: focusedWindowBridge,
                tabMatches: [],
                decision: "missing",
                reason: "target window is not focused"
            )
        }

        let items = targetWindow.tabs.map { tab in
            matchTab(tab, axTabs: axTabs)
        }
        let decisions = items.map(\.decision)
        let decision: String
        let reason: String
        if decisions.contains("ambiguous") {
            decision = "ambiguous"
            reason = "one or more persisted tabs matched multiple AX candidates"
        } else if decisions.contains("missing") {
            decision = "missing"
            reason = "one or more persisted tabs are missing from AX focused tabs"
        } else {
            decision = "matched"
            reason = "all persisted tabs matched exactly one AX focused tab"
        }

        return FocusedTabsBridgeRecord(
            requestedWindowID: targetWindow.windowID,
            targetWindowTitle: targetWindow.activeTitle,
            focusedWindowBridge: focusedWindowBridge,
            tabMatches: items,
            decision: decision,
            reason: reason
        )
    }

    private func matchTab(_ tab: PersistedTabRecord, axTabs: [FocusedTabRecord]) -> FocusedTabBridgeItem {
        let candidates = axTabs.compactMap { ax -> FocusedTabMatchCandidate? in
            guard normalized(ax.title) == normalized(tab.title) else { return nil }
            let indexPenalty = ax.index == tab.index ? 0 : 10
            return FocusedTabMatchCandidate(
                index: ax.index,
                title: ax.title,
                role: ax.role,
                selected: ax.selected,
                score: indexPenalty,
                reason: ax.index == tab.index ? "title=exact,index=exact" : "title=exact,index=mismatch persisted=\(tab.index) ax=\(ax.index)"
            )
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.index < rhs.index
        }

        if candidates.count == 1 {
            return FocusedTabBridgeItem(
                persistedTab: tab,
                candidates: candidates,
                decision: "matched",
                reason: candidates[0].reason
            )
        }
        if candidates.count > 1 {
            return FocusedTabBridgeItem(
                persistedTab: tab,
                candidates: candidates,
                decision: "ambiguous",
                reason: "multiple AX tabs have the same title"
            )
        }
        return FocusedTabBridgeItem(
            persistedTab: tab,
            candidates: [],
            decision: "missing",
            reason: "no AX tab with exact title"
        )
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

