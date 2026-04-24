import ApplicationServices
import Foundation

final class AXElement {
    let raw: AXUIElement

    init(_ raw: AXUIElement) {
        self.raw = raw
    }

    static func applicationElement(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    func isEqualTo(_ other: AXElement) -> Bool {
        CFEqual(raw, other.raw)
    }

    func attributeNames() -> [String] {
        var names: CFArray?
        let status = AXUIElementCopyAttributeNames(raw, &names)
        guard status == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    func parameterizedAttributeNames() -> [String] {
        var names: CFArray?
        let status = AXUIElementCopyParameterizedAttributeNames(raw, &names)
        guard status == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    func attributeValue(_ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(raw, name, &value)
        guard status == .success else { return nil }
        return value
    }

    func stringAttribute(_ name: CFString) -> String? {
        attributeValue(name) as? String
    }

    func boolAttribute(_ name: CFString) -> Bool? {
        if let value = attributeValue(name) as? Bool {
            return value
        }
        if let number = attributeValue(name) as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    func childrenAttribute(_ name: CFString) -> [AXElement] {
        guard let values = attributeValue(name) as? [AXUIElement] else { return [] }
        return values.map(AXElement.init)
    }

    func role() -> String? {
        stringAttribute(kAXRoleAttribute as CFString)
    }

    func title() -> String? {
        stringAttribute(kAXTitleAttribute as CFString)
    }

    func valueString() -> String? {
        if let str = attributeValue(kAXValueAttribute as CFString) as? String {
            return str
        }
        return nil
    }

    func isSelected() -> Bool? {
        boolAttribute(kAXSelectedAttribute as CFString)
    }

    func frame() -> CGRect? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(raw, "AXFrame" as CFString, &value)
        guard status == .success, let value else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        let ok = AXValueGetValue(axValue, .cgRect, &rect)
        return ok ? rect : nil
    }

    func children() -> [AXElement] {
        childrenAttribute(kAXChildrenAttribute as CFString)
    }

    func windows() -> [AXElement] {
        childrenAttribute(kAXWindowsAttribute as CFString)
    }

    func focusedWindow() -> AXElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(raw, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success, let value else {
            return nil
        }
        return AXElement(value as! AXUIElement)
    }

    func actionNames() -> [String] {
        var names: CFArray?
        let status = AXUIElementCopyActionNames(raw, &names)
        guard status == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    @discardableResult
    func performAction(_ action: CFString) -> Bool {
        AXUIElementPerformAction(raw, action) == .success
    }

    func primaryLabel() -> String {
        if let title = title(), !title.isEmpty {
            return title
        }
        if let value = valueString(), !value.isEmpty {
            return value
        }
        return "<untitled>"
    }

    func descendantElements(role targetRole: String, maxDepth: Int = 12) -> [AXElement] {
        var result: [AXElement] = []
        var queue: [(AXElement, Int)] = [(self, 0)]

        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if current.role() == targetRole {
                result.append(current)
            }
            if depth >= maxDepth { continue }
            for child in current.children() {
                queue.append((child, depth + 1))
            }
        }

        return result
    }
}
