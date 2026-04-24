import Foundation

struct AXTreeDumper {
    let maxDepth: Int
    let maxChildrenPerNode: Int

    init(maxDepth: Int = 6, maxChildrenPerNode: Int = 40) {
        self.maxDepth = maxDepth
        self.maxChildrenPerNode = maxChildrenPerNode
    }

    func dump(element: AXElement) -> String {
        var lines: [String] = []
        recurse(element, depth: 0, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private func recurse(_ element: AXElement, depth: Int, lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let role = element.role() ?? "UnknownRole"
        let title = element.title() ?? ""
        let value = element.valueString() ?? ""
        let selected = element.isSelected().map { "\($0)" } ?? "n/a"
        let actions = element.actionNames().joined(separator: ",")

        lines.append("\(indent)\(role) title='\(title)' value='\(value)' selected=\(selected) actions=[\(actions)]")

        guard depth < maxDepth else { return }
        let children = element.children()
        if children.isEmpty { return }

        for child in children.prefix(maxChildrenPerNode) {
            recurse(child, depth: depth + 1, lines: &lines)
        }
    }
}
