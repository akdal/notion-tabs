import ApplicationServices
import Foundation

final class AXElementV2 {
    let raw: AXUIElement

    init(_ raw: AXUIElement) {
        self.raw = raw
    }

    static func application(pid: pid_t) -> AXElementV2 {
        AXElementV2(AXUIElementCreateApplication(pid))
    }

    func attribute(_ name: CFString) -> AnyObject? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(raw, name, &value)
        guard status == .success, let value else { return nil }
        return value
    }

    func attributeNames() -> [String] {
        var names: CFArray?
        let status = AXUIElementCopyAttributeNames(raw, &names)
        guard status == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    func string(_ name: CFString) -> String? {
        attribute(name) as? String
    }

    func bool(_ name: CFString) -> Bool? {
        if let value = attribute(name) as? Bool { return value }
        if let value = attribute(name) as? NSNumber { return value.boolValue }
        return nil
    }

    func elements(_ name: CFString) -> [AXElementV2] {
        guard let values = attribute(name) as? [AXUIElement] else { return [] }
        return values.map(AXElementV2.init)
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

    func children() -> [AXElementV2] {
        elements(kAXChildrenAttribute as CFString)
    }

    func windows() -> [AXElementV2] {
        elements(kAXWindowsAttribute as CFString)
    }

    func focusedWindow() -> AXElementV2? {
        guard let value = attribute(kAXFocusedWindowAttribute as CFString), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return AXElementV2(unsafeBitCast(value, to: AXUIElement.self))
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

    func isSelected() -> Bool? {
        bool(kAXSelectedAttribute as CFString)
    }

    func descendants(role targetRole: String, maxDepth: Int) -> [AXElementV2] {
        var result: [AXElementV2] = []
        var queue: [(AXElementV2, Int)] = [(self, 0)]
        while !queue.isEmpty {
            let (item, depth) = queue.removeFirst()
            if item.role() == targetRole { result.append(item) }
            if depth >= maxDepth { continue }
            for child in item.children() {
                queue.append((child, depth + 1))
            }
        }
        return result
    }
}

enum AXWindowInspector {
    static func focusedWindowRecord(pid: pid_t) -> AXWindowRecord? {
        guard let focused = AXElementV2.application(pid: pid).focusedWindow() else {
            return nil
        }
        return AXWindowRecord(
            index: 1,
            title: focused.title(),
            role: focused.role(),
            frame: focused.frame().map(RectRecord.init),
            isFocused: focused.bool(kAXFocusedAttribute as CFString),
            isMain: focused.bool(kAXMainAttribute as CFString),
            isMinimized: focused.bool(kAXMinimizedAttribute as CFString),
            actions: focused.actions()
        )
    }
}

struct AXTreeDumperV2 {
    let maxDepth: Int
    let maxChildren: Int

    func dump(element: AXElementV2) -> String {
        var lines: [String] = []
        walk(element: element, depth: 0, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private func walk(element: AXElementV2, depth: Int, lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let title = sanitize(element.title())
        let value = sanitize(element.valueString() ?? "")
        let frame = element.frame().map { String(format: "(x:%.0f,y:%.0f,w:%.0f,h:%.0f)", $0.origin.x, $0.origin.y, $0.width, $0.height) } ?? "<nil>"
        let selected = element.isSelected().map(String.init) ?? "<nil>"
        let actions = element.actions().joined(separator: ",")
        let attrs = element.attributeNames().sorted().joined(separator: ",")
        lines.append("\(indent)\(element.role()) title='\(title)' value='\(value)' selected=\(selected) frame=\(frame) actions=[\(actions)] attrs=[\(attrs)]")

        guard depth < maxDepth else { return }
        for child in element.children().prefix(maxChildren) {
            walk(element: child, depth: depth + 1, lines: &lines)
        }
    }

    private func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }
}
