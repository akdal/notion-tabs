import Foundation
import CoreGraphics

struct NotionTabSnapshot {
    let index: Int
    let title: String
    let isSelected: Bool
    let rawElement: AXElement
}

struct NotionWindowSnapshot {
    let index: Int
    let title: String
    let rawElement: AXElement
    let tabs: [NotionTabSnapshot]
}

struct NotionWindowServerSnapshot {
    let index: Int
    let windowID: CGWindowID
    let title: String?
    let bounds: CGRect
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool?
}

struct NotionShareableWindowSnapshot {
    let index: Int
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let isOnScreen: Bool
    let isActive: Bool
}

struct NotionPersistedTabSnapshot {
    let index: Int
    let tabID: String
    let title: String
}

struct NotionPersistedWindowSnapshot {
    let index: Int
    let windowID: String
    let activeTitle: String
    let bounds: CGRect
    let tabs: [NotionPersistedTabSnapshot]
}

struct NotionPersistedStateSnapshot {
    let modifiedAt: Date?
    let windows: [NotionPersistedWindowSnapshot]
}
