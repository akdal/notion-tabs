import Foundation

struct WindowBridgeRecord: Codable {
    let persistedWindow: PersistedWindowRecord
    let candidates: [WindowMatchCandidate]
    let decision: String
    let reason: String
}

struct WindowMatchCandidate: Codable {
    let source: String
    let index: Int
    let windowID: String?
    let title: String?
    let frame: RectRecord
    let score: Int
    let titleDecision: String
    let frameDistance: Double
    let reason: String
}

struct MenuBridgeRecord: Codable {
    let persistedWindow: PersistedWindowRecord
    let candidates: [MenuMatchCandidate]
    let decision: String
    let reason: String
}

struct MenuMatchCandidate: Codable {
    let index: Int
    let title: String
    let category: String
    let score: Int
    let reason: String
}

struct FocusWindowActionRecord: Codable {
    let requestedWindowID: String
    let strategy: String
    let targetTitle: String
    let menuCandidate: MenuMatchCandidate?
    let preFocusedWindow: AXWindowRecord?
    let postFocusedWindow: AXWindowRecord?
    let action: String?
    let decision: String
    let reason: String
    let elapsedMS: Int
}

struct FocusedWindowBridgeRecord: Codable {
    let requestedWindowID: String
    let targetTitle: String
    let targetBounds: RectRecord
    let focusedWindow: AXWindowRecord?
    let decision: String
    let reason: String
    let titleMatches: Bool
    let frameDistance: Double?
}

struct FocusedTabsBridgeRecord: Codable {
    let requestedWindowID: String
    let targetWindowTitle: String
    let focusedWindowBridge: FocusedWindowBridgeRecord
    let tabMatches: [FocusedTabBridgeItem]
    let decision: String
    let reason: String
}

struct FocusedTabBridgeItem: Codable {
    let persistedTab: PersistedTabRecord
    let candidates: [FocusedTabMatchCandidate]
    let decision: String
    let reason: String
}

struct FocusedTabMatchCandidate: Codable {
    let index: Int
    let title: String
    let role: String
    let selected: Bool?
    let score: Int
    let reason: String
}

struct TabObservationBridgeRecord: Codable {
    let requestedWindowID: String
    let targetWindowTitle: String
    let focusedWindowBridge: FocusedWindowBridgeRecord
    let axCandidates: [TabObservationCandidate]
    let tabMatches: [TabObservationMatchItem]
    let decision: String
    let reason: String
}

struct TabObservationCandidate: Codable {
    let index: Int
    let depth: Int
    let role: String
    let label: String
    let labelSource: String
    let frame: RectRecord?
    let selected: Bool?
    let actions: [String]
    let nearTop: Bool
    let clickable: Bool
}

struct TabObservationMatchItem: Codable {
    let persistedTab: PersistedTabRecord
    let candidates: [TabObservationCandidate]
    let decision: String
    let reason: String
}

struct FocusTabActionRecord: Codable {
    let requestedWindowID: String
    let requestedTabID: String?
    let requestedTabTitle: String
    let targetWindowTitle: String
    let strategy: String
    let preActiveTitle: String
    let postActiveTitle: String?
    let preFocusedWindow: AXWindowRecord?
    let postFocusedWindow: AXWindowRecord?
    let candidate: TabObservationCandidate?
    let action: String?
    let pressed: Bool
    let stateChangedToTarget: Bool
    let focusedTitleMatchesTarget: Bool
    let decision: String
    let reason: String
    let elapsedMS: Int
}
