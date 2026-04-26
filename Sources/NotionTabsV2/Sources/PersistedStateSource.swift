import CoreGraphics
import Foundation

enum PersistedStateSourceError: Error, CustomStringConvertible {
    case missingFile(String)
    case invalidRoot

    var description: String {
        switch self {
        case let .missingFile(path): return "state file missing: \(path)"
        case .invalidRoot: return "state file root is not an object"
        }
    }
}

struct PersistedStateSource {
    func read() throws -> PersistedSnapshotRecord {
        let url = stateFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PersistedStateSourceError.missingFile(url.path)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = attributes[.modificationDate] as? Date
        let size = attributes[.size] as? NSNumber
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersistedStateSourceError.invalidRoot
        }

        let history = root["history"] as? [String: Any] ?? [:]
        let appRestorationState = history["appRestorationState"] as? [String: Any] ?? [:]
        let rawWindows = appRestorationState["windows"] as? [[String: Any]] ?? []
        let windows = rawWindows.enumerated().map { offset, rawWindow in
            parseWindow(rawWindow, index: offset + 1)
        }

        return PersistedSnapshotRecord(
            path: url.path,
            exists: true,
            modifiedAt: modifiedAt.map(Self.isoFormatter.string),
            ageSeconds: modifiedAt.map { Date().timeIntervalSince($0) },
            byteSize: size?.intValue ?? data.count,
            windows: windows
        )
    }

    private func parseWindow(_ rawWindow: [String: Any], index: Int) -> PersistedWindowRecord {
        let windowID = rawWindow["windowId"] as? String ?? ""
        let displayState = rawWindow["displayState"] as? [String: Any] ?? [:]
        let normalBounds = displayState["normalBounds"] as? [String: Any] ?? [:]
        let bounds = CGRect(
            x: normalBounds["x"] as? CGFloat ?? 0,
            y: normalBounds["y"] as? CGFloat ?? 0,
            width: normalBounds["width"] as? CGFloat ?? 0,
            height: normalBounds["height"] as? CGFloat ?? 0
        )
        let rawTabs = rawWindow["tabs"] as? [[String: Any]] ?? []
        let activeTabMap = rawWindow["activeTabIdMap"] as? [String: Any] ?? [:]
        let activeTabID = activeTabMap["ungrouped"] as? String ?? ""
        let activeTitle = rawTabs.first { ($0["tabId"] as? String) == activeTabID }?["title"] as? String ?? ""
        let tabs = rawTabs.enumerated().compactMap { offset, rawTab -> PersistedTabRecord? in
            guard let title = rawTab["title"] as? String else { return nil }
            return PersistedTabRecord(
                index: offset + 1,
                tabID: rawTab["tabId"] as? String ?? "",
                title: title
            )
        }

        return PersistedWindowRecord(
            index: index,
            windowID: windowID,
            activeTitle: activeTitle,
            bounds: RectRecord(bounds),
            tabs: tabs
        )
    }

    private func stateFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notion/state.json")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

