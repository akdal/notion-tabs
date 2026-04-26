import CoreGraphics
import Foundation

struct ProcessRecord: Codable {
    let found: Bool
    let pid: Int?
    let bundleIdentifier: String?
    let localizedName: String?
    let isActive: Bool?
    let isHidden: Bool?
}

struct PersistedSnapshotRecord: Codable {
    let path: String
    let exists: Bool
    let modifiedAt: String?
    let ageSeconds: Double?
    let byteSize: Int?
    let windows: [PersistedWindowRecord]
}

struct PersistedWindowRecord: Codable {
    let index: Int
    let windowID: String
    let activeTitle: String
    let bounds: RectRecord
    let tabs: [PersistedTabRecord]
}

struct PersistedTabRecord: Codable {
    let index: Int
    let tabID: String
    let title: String
}

struct LiveWindowRecord: Codable {
    let source: String
    let index: Int
    let windowID: String?
    let title: String?
    let frame: RectRecord
    let isOnScreen: Bool?
    let isActive: Bool?
    let layer: Int?
    let alpha: Double?
}

struct AXWindowRecord: Codable {
    let index: Int
    let title: String
    let role: String
    let frame: RectRecord?
    let isFocused: Bool?
    let isMain: Bool?
    let isMinimized: Bool?
    let actions: [String]
}

struct MenuItemRecord: Codable {
    let index: Int
    let title: String
    let role: String
    let category: String
    let selected: Bool?
    let actions: [String]
}

struct FocusedTabRecord: Codable {
    let index: Int
    let title: String
    let role: String
    let value: String?
    let frame: RectRecord?
    let selected: Bool?
    let actions: [String]
}

struct StateSampleRecord: Codable {
    let index: Int
    let elapsedMS: Int
    let sampledAt: String
    let persistedModifiedAt: String?
    let persistedAgeSeconds: Double?
    let persistedWindows: [PersistedWindowStateRecord]
    let axFocusedWindow: AXWindowRecord?
    let axFocusedTabsStrict: [FocusedTabRecord]
    let axFocusedTabsRaw: [FocusedTabRecord]
}

struct PersistedWindowStateRecord: Codable {
    let windowID: String
    let activeTitle: String
    let tabCount: Int
}

struct RectRecord: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
}

extension Encodable {
    func jsonValue() -> JSONValue {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(self),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return .null
        }
        return JSONValue.fromJSONObject(object)
    }
}

extension JSONValue {
    static func fromJSONObject(_ object: Any) -> JSONValue {
        switch object {
        case let value as String:
            return .string(value)
        case let value as Int:
            return .int(value)
        case let value as Double:
            return .double(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            let double = value.doubleValue
            if double.rounded() == double {
                return .int(value.intValue)
            }
            return .double(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let values as [Any]:
            return .array(values.map(JSONValue.fromJSONObject))
        case let values as [String: Any]:
            return .object(values.mapValues(JSONValue.fromJSONObject))
        default:
            return .null
        }
    }
}
