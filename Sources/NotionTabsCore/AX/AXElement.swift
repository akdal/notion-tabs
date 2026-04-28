import ApplicationServices
import CoreGraphics
import Foundation

final class AXElement {
    let raw: AXUIElement

    init(_ raw: AXUIElement) {
        self.raw = raw
    }

    static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    func attribute(_ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(raw, name, &value)
        guard status == .success, let value else { return nil }
        return value
    }

    func string(_ name: CFString) -> String? {
        attribute(name) as? String
    }

    func bool(_ name: CFString) -> Bool? {
        if let value = attribute(name) as? Bool { return value }
        if let value = attribute(name) as? NSNumber { return value.boolValue }
        return nil
    }

    func role() -> String {
        string(kAXRoleAttribute as CFString) ?? ""
    }

    func title() -> String {
        string(kAXTitleAttribute as CFString) ?? ""
    }

    func valueString() -> String? {
        attribute(kAXValueAttribute as CFString) as? String
    }

    func frame() -> CGRect? {
        guard let value = attribute("AXFrame" as CFString), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }

    func elements(_ name: CFString) -> [AXElement] {
        guard let values = attribute(name) as? [AXUIElement] else { return [] }
        return values.map(AXElement.init)
    }

    func children() -> [AXElement] {
        elements(kAXChildrenAttribute as CFString)
    }

    func focusedWindow() -> AXElement? {
        guard let value = attribute(kAXFocusedWindowAttribute as CFString), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return AXElement(unsafeBitCast(value, to: AXUIElement.self))
    }

    func windows() -> [AXElement] {
        elements(kAXWindowsAttribute as CFString)
    }

    func actions() -> [String] {
        var names: CFArray?
        let status = AXUIElementCopyActionNames(raw, &names)
        guard status == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    func perform(_ action: CFString) -> Bool {
        AXUIElementPerformAction(raw, action) == .success
    }
}
