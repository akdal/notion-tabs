import CoreGraphics
import Foundation

struct NotionWindowServerScanner {
    func scanWindows(pid: pid_t) -> [NotionWindowServerSnapshot] {
        guard let rows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let candidates = rows.compactMap { row -> NotionWindowServerSnapshot? in
            guard let ownerPID = row[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                return nil
            }
            let layer = row[kCGWindowLayer as String] as? Int ?? -1
            let alpha = row[kCGWindowAlpha as String] as? Double ?? 0
            guard layer == 0, alpha > 0 else { return nil }

            let boundsDict = row[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            // Filter obvious non-document surfaces such as tiny utility strips.
            guard bounds.width >= 400, bounds.height >= 250 else { return nil }

            let onscreenRaw = row[kCGWindowIsOnscreen as String] as? Int
            let isOnscreen = onscreenRaw.map { $0 != 0 }
            let title = (row[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let windowID = row[kCGWindowNumber as String] as? CGWindowID ?? 0

            return NotionWindowServerSnapshot(
                index: 0,
                windowID: windowID,
                title: title?.isEmpty == true ? nil : title,
                bounds: bounds,
                layer: layer,
                alpha: alpha,
                isOnscreen: isOnscreen
            )
        }

        var unique: [NotionWindowServerSnapshot] = []
        var seen: Set<String> = []
        for candidate in candidates {
            let key = "\(Int(candidate.bounds.origin.x))|\(Int(candidate.bounds.origin.y))|\(Int(candidate.bounds.width))|\(Int(candidate.bounds.height))|\(candidate.title ?? "")"
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(candidate)
        }

        return unique.enumerated().map { idx, item in
            NotionWindowServerSnapshot(
                index: idx + 1,
                windowID: item.windowID,
                title: item.title,
                bounds: item.bounds,
                layer: item.layer,
                alpha: item.alpha,
                isOnscreen: item.isOnscreen
            )
        }
    }
}
