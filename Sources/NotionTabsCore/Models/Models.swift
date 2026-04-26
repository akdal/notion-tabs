import CoreGraphics
import Foundation

public struct WindowRef: Equatable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public struct TabRef: Equatable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public struct RectSnapshot: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }
}

public struct TabSnapshot: Equatable, Sendable {
    public let id: String
    public let index: Int
    public let title: String
    public let isPersistedActive: Bool
    public let isAXFocused: Bool

    public init(id: String, index: Int, title: String, isPersistedActive: Bool, isAXFocused: Bool) {
        self.id = id
        self.index = index
        self.title = title
        self.isPersistedActive = isPersistedActive
        self.isAXFocused = isAXFocused
    }
}

public struct WindowSnapshot: Equatable, Sendable {
    public let id: String
    public let index: Int
    public let persistedActiveTitle: String
    public let frame: RectSnapshot
    public let isAXFocused: Bool
    public let isInWindowMenu: Bool
    public let tabs: [TabSnapshot]

    public init(
        id: String,
        index: Int,
        persistedActiveTitle: String,
        frame: RectSnapshot,
        isAXFocused: Bool,
        isInWindowMenu: Bool,
        tabs: [TabSnapshot]
    ) {
        self.id = id
        self.index = index
        self.persistedActiveTitle = persistedActiveTitle
        self.frame = frame
        self.isAXFocused = isAXFocused
        self.isInWindowMenu = isInWindowMenu
        self.tabs = tabs
    }
}

public struct ListSnapshot: Equatable, Sendable {
    public let focusedTitle: String?
    public let statePath: String
    public let stateModifiedAt: Date?
    public let windows: [WindowSnapshot]

    public init(focusedTitle: String?, statePath: String, stateModifiedAt: Date?, windows: [WindowSnapshot]) {
        self.focusedTitle = focusedTitle
        self.statePath = statePath
        self.stateModifiedAt = stateModifiedAt
        self.windows = windows
    }
}

public struct FocusResult: Equatable, Sendable {
    public let success: Bool
    public let targetTitle: String
    public let focusedTitle: String?
    public let strategy: String?
    public let message: String

    public init(success: Bool, targetTitle: String, focusedTitle: String?, strategy: String?, message: String) {
        self.success = success
        self.targetTitle = targetTitle
        self.focusedTitle = focusedTitle
        self.strategy = strategy
        self.message = message
    }
}

public enum NotionTabsError: Error, LocalizedError {
    case notionNotRunning
    case stateUnavailable(String)
    case windowNotFound(String)
    case tabNotFound(String)
    case windowMenuUnavailable
    case focusedWindowUnavailable
    case tabButtonUnavailable(String)
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notionNotRunning:
            return "Notion is not running."
        case let .stateUnavailable(message):
            return "Notion state is unavailable: \(message)"
        case let .windowNotFound(ref):
            return "Window not found: \(ref)"
        case let .tabNotFound(ref):
            return "Tab not found: \(ref)"
        case .windowMenuUnavailable:
            return "Notion Window menu is unavailable."
        case .focusedWindowUnavailable:
            return "Focused Notion window is unavailable."
        case let .tabButtonUnavailable(title):
            return "Tab button is unavailable: \(title)"
        case let .actionFailed(message):
            return message
        }
    }

    public var code: String {
        switch self {
        case .notionNotRunning:
            return "NOTION_NOT_RUNNING"
        case .stateUnavailable:
            return "STATE_UNAVAILABLE"
        case .windowNotFound:
            return "WINDOW_NOT_FOUND"
        case .tabNotFound:
            return "TAB_NOT_FOUND"
        case .windowMenuUnavailable:
            return "WINDOW_MENU_UNAVAILABLE"
        case .focusedWindowUnavailable:
            return "FOCUSED_WINDOW_UNAVAILABLE"
        case .tabButtonUnavailable:
            return "TAB_BUTTON_UNAVAILABLE"
        case .actionFailed:
            return "ACTION_FAILED"
        }
    }
}
