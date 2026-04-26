import CoreGraphics
import Foundation

struct PersistedState {
    let path: String
    let modifiedAt: Date?
    let windows: [PersistedWindow]
}

struct PersistedWindow {
    let id: String
    let index: Int
    let activeTitle: String
    let frame: CGRect
    let tabs: [PersistedTab]
}

struct PersistedTab {
    let id: String
    let index: Int
    let title: String
}

struct NotionStateStore {
    private let statePath: String

    init(statePath: String = "\(NSHomeDirectory())/Library/Application Support/Notion/state.json") {
        self.statePath = statePath
    }

    func read() throws -> PersistedState {
        let url = URL(fileURLWithPath: statePath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NotionTabsError.stateUnavailable(error.localizedDescription)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NotionTabsError.stateUnavailable(error.localizedDescription)
        }

        guard let root = object as? [String: Any] else {
            throw NotionTabsError.stateUnavailable("root is not an object")
        }

        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: statePath)[.modificationDate]) as? Date
        return PersistedState(
            path: statePath,
            modifiedAt: modifiedAt,
            windows: parseRestorationWindows(root: root)
        )
    }

    private func parseRestorationWindows(root: [String: Any]) -> [PersistedWindow] {
        let history = root["history"] as? [String: Any] ?? [:]
        let appRestorationState = history["appRestorationState"] as? [String: Any] ?? [:]
        let rawWindows = appRestorationState["windows"] as? [[String: Any]] ?? []
        return rawWindows.enumerated().map { offset, rawWindow in
            parseWindow(rawWindow, index: offset + 1)
        }
    }

    private func parseWindow(_ rawWindow: [String: Any], index: Int) -> PersistedWindow {
        let windowID = rawWindow["windowId"] as? String ?? ""
        let rawTabs = rawWindow["tabs"] as? [[String: Any]] ?? []
        let activeTabMap = rawWindow["activeTabIdMap"] as? [String: Any] ?? [:]
        let activeTabID = activeTabMap["ungrouped"] as? String ?? ""
        let tabs = rawTabs.enumerated().compactMap { offset, rawTab -> PersistedTab? in
            guard let title = rawTab["title"] as? String else { return nil }
            return PersistedTab(
                id: rawTab["tabId"] as? String ?? "",
                index: offset + 1,
                title: title
            )
        }
        let activeTitle = tabs.first(where: { $0.id == activeTabID })?.title ?? tabs.last?.title ?? ""
        let displayState = rawWindow["displayState"] as? [String: Any] ?? [:]
        let normalBounds = displayState["normalBounds"] as? [String: Any] ?? [:]
        return PersistedWindow(
            id: windowID,
            index: index,
            activeTitle: activeTitle,
            frame: frame(bounds: normalBounds),
            tabs: tabs
        )
    }

    private func frame(bounds: [String: Any]) -> CGRect {
        let x = number(bounds["x"]) ?? number(bounds["X"]) ?? 0
        let y = number(bounds["y"]) ?? number(bounds["Y"]) ?? 0
        let width = number(bounds["width"]) ?? number(bounds["Width"]) ?? 0
        let height = number(bounds["height"]) ?? number(bounds["Height"]) ?? 0
        return CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }
}
