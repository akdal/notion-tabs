import CoreGraphics
import Foundation
import ScreenCaptureKit

struct LiveWindowSource {
    func readQuartz(pid: pid_t) -> [LiveWindowRecord] {
        guard let rows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let records = rows.compactMap { row -> LiveWindowRecord? in
            guard let ownerPID = row[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else {
                return nil
            }
            let layer = row[kCGWindowLayer as String] as? Int ?? -1
            let alpha = row[kCGWindowAlpha as String] as? Double ?? 0
            guard layer == 0, alpha > 0 else { return nil }
            let boundsDict = row[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let frame = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )
            guard frame.width >= 400, frame.height >= 250 else { return nil }
            let windowID = row[kCGWindowNumber as String].map { "\($0)" }
            let onscreenRaw = row[kCGWindowIsOnscreen as String] as? Int
            let title = (row[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LiveWindowRecord(
                source: "quartz",
                index: 0,
                windowID: windowID,
                title: title?.isEmpty == true ? nil : title,
                frame: RectRecord(frame),
                isOnScreen: onscreenRaw.map { $0 != 0 },
                isActive: nil,
                layer: layer,
                alpha: alpha
            )
        }

        return records.enumerated().map { offset, record in
            LiveWindowRecord(
                source: record.source,
                index: offset + 1,
                windowID: record.windowID,
                title: record.title,
                frame: record.frame,
                isOnScreen: record.isOnScreen,
                isActive: record.isActive,
                layer: record.layer,
                alpha: record.alpha
            )
        }
    }

    func readScreenCapture(bundleIdentifier: String?, onScreenOnly: Bool) -> [LiveWindowRecord] {
        let semaphore = DispatchSemaphore(value: 0)
        var windows: [SCWindow] = []

        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreenOnly)
                windows = content.windows.filter { window in
                    guard let app = window.owningApplication else { return false }
                    if let bundleIdentifier {
                        return app.bundleIdentifier == bundleIdentifier
                    }
                    return app.applicationName.localizedCaseInsensitiveContains("notion")
                }
                .filter { window in
                    window.windowLayer == 0 && window.frame.width >= 400 && window.frame.height >= 250
                }
            } catch {
                windows = []
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return windows.enumerated().map { offset, window in
            let isActive: Bool?
            if #available(macOS 13.1, *) {
                isActive = window.isActive
            } else {
                isActive = nil
            }
            return LiveWindowRecord(
                source: onScreenOnly ? "screen_capture_onscreen" : "screen_capture_all",
                index: offset + 1,
                windowID: "\(window.windowID)",
                title: window.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                frame: RectRecord(window.frame),
                isOnScreen: window.isOnScreen,
                isActive: isActive,
                layer: window.windowLayer,
                alpha: nil
            )
        }
    }
}

