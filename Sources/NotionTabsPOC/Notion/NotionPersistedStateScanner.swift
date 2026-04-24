import Foundation

enum NotionPersistedStateError: Error, CustomStringConvertible {
    case stateFileMissing(String)
    case invalidFormat

    var description: String {
        switch self {
        case let .stateFileMissing(path):
            return "Notion state file not found: \(path)"
        case .invalidFormat:
            return "Notion state file format is invalid."
        }
    }
}

struct NotionPersistedStateScanner {
    func loadSnapshot() throws -> NotionPersistedStateSnapshot {
        let url = stateFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NotionPersistedStateError.stateFileMissing(url.path)
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionPersistedStateError.invalidFormat
        }

        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let history = root["history"] as? [String: Any] ?? [:]
        let appRestorationState = history["appRestorationState"] as? [String: Any] ?? [:]
        let windows = appRestorationState["windows"] as? [[String: Any]] ?? []

        let snapshots = windows.enumerated().map { index, window in
            let windowID = window["windowId"] as? String ?? ""
            let displayState = window["displayState"] as? [String: Any] ?? [:]
            let normalBounds = displayState["normalBounds"] as? [String: Any] ?? [:]
            let bounds = CGRect(
                x: normalBounds["x"] as? CGFloat ?? 0,
                y: normalBounds["y"] as? CGFloat ?? 0,
                width: normalBounds["width"] as? CGFloat ?? 0,
                height: normalBounds["height"] as? CGFloat ?? 0
            )

            let activeTabMap = window["activeTabIdMap"] as? [String: Any] ?? [:]
            let activeTabID = activeTabMap["ungrouped"] as? String ?? ""
            let tabs = (window["tabs"] as? [[String: Any]] ?? []).enumerated().compactMap { idx, tab -> NotionPersistedTabSnapshot? in
                guard let title = tab["title"] as? String else { return nil }
                let tabID = tab["tabId"] as? String ?? ""
                return NotionPersistedTabSnapshot(index: idx + 1, tabID: tabID, title: title)
            }
            let activeTitle = (window["tabs"] as? [[String: Any]] ?? []).first(where: { ($0["tabId"] as? String) == activeTabID })?["title"] as? String ?? "<unknown>"

            return NotionPersistedWindowSnapshot(
                index: index + 1,
                windowID: windowID,
                activeTitle: activeTitle,
                bounds: bounds,
                tabs: tabs
            )
        }

        return NotionPersistedStateSnapshot(modifiedAt: modifiedAt, windows: snapshots)
    }

    private func stateFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notion/state.json")
    }
}
