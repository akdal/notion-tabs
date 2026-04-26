import Foundation

struct MenuMatcher {
    func match(persisted: [PersistedWindowRecord], menuItems: [MenuItemRecord]) -> [MenuBridgeRecord] {
        let documentItems = menuItems.filter { $0.category == "document_candidate" }
        return persisted.map { window in
            let candidates = documentItems.map { candidate(window: window, item: $0) }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score < rhs.score }
                    return lhs.index < rhs.index
                }
            return decide(window: window, candidates: candidates)
        }
    }

    private func candidate(window: PersistedWindowRecord, item: MenuItemRecord) -> MenuMatchCandidate {
        let exact = normalized(window.activeTitle) == normalized(item.title)
        return MenuMatchCandidate(
            index: item.index,
            title: item.title,
            category: item.category,
            score: exact ? 0 : 100,
            reason: exact ? "title=exact" : "title=mismatch"
        )
    }

    private func decide(window: PersistedWindowRecord, candidates: [MenuMatchCandidate]) -> MenuBridgeRecord {
        let exactMatches = candidates.filter { $0.score == 0 }
        if exactMatches.count == 1 {
            return MenuBridgeRecord(
                persistedWindow: window,
                candidates: exactMatches,
                decision: "matched",
                reason: "one exact menu title match"
            )
        }
        if exactMatches.count > 1 {
            return MenuBridgeRecord(
                persistedWindow: window,
                candidates: exactMatches,
                decision: "ambiguous",
                reason: "multiple exact menu title matches"
            )
        }
        return MenuBridgeRecord(
            persistedWindow: window,
            candidates: Array(candidates.prefix(5)),
            decision: "missing",
            reason: "no exact document-window menu title match"
        )
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

