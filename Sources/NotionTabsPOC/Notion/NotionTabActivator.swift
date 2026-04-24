import ApplicationServices
import AppKit
import Foundation

enum TabActivationError: Error, CustomStringConvertible {
    case invalidWindowIndex
    case invalidTabIndex
    case cannotActivateNotion
    case missingSupportedAction
    case failedAction(String)

    var description: String {
        switch self {
        case .invalidWindowIndex: return "Window index is out of range."
        case .invalidTabIndex: return "Tab index is out of range."
        case .cannotActivateNotion: return "Could not bring Notion to foreground."
        case .missingSupportedAction: return "No supported accessibility action found for tab."
        case let .failedAction(action): return "Failed to run accessibility action: \(action)"
        }
    }
}

struct NotionTabActivator {
    private let appActivationService = AppActivationService()

    func activate(
        notionApp: NSRunningApplication,
        windows: [NotionWindowSnapshot],
        windowIndex: Int,
        tabIndex: Int
    ) throws -> String {
        guard let window = windows.first(where: { $0.index == windowIndex }) else {
            throw TabActivationError.invalidWindowIndex
        }
        guard let tab = window.tabs.first(where: { $0.index == tabIndex }) else {
            throw TabActivationError.invalidTabIndex
        }
        guard appActivationService.activate(notionApp) else {
            throw TabActivationError.cannotActivateNotion
        }

        let actions = tab.rawElement.actionNames()
        if actions.contains(kAXPressAction as String) {
            let ok = tab.rawElement.performAction(kAXPressAction as CFString)
            if !ok { throw TabActivationError.failedAction(kAXPressAction as String) }
            return kAXPressAction as String
        }

        if actions.contains(kAXPickAction as String) {
            let ok = tab.rawElement.performAction(kAXPickAction as CFString)
            if !ok { throw TabActivationError.failedAction(kAXPickAction as String) }
            return kAXPickAction as String
        }

        throw TabActivationError.missingSupportedAction
    }
}
