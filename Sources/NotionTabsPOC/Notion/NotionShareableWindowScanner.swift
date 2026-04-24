import Foundation
import ScreenCaptureKit

struct NotionShareableWindowScanner {
    func scanWindows(bundleIdentifier: String?, onScreenOnly: Bool) -> [NotionShareableWindowSnapshot] {
        let result = loadShareableContent(bundleIdentifier: bundleIdentifier, onScreenOnly: onScreenOnly)
        return result.enumerated().map { idx, window in
            let isActive: Bool
            if #available(macOS 13.1, *) {
                isActive = window.isActive
            } else {
                isActive = false
            }
            return NotionShareableWindowSnapshot(
                index: idx + 1,
                windowID: window.windowID,
                title: window.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                frame: window.frame,
                isOnScreen: window.isOnScreen,
                isActive: isActive
            )
        }
    }

    private func loadShareableContent(bundleIdentifier: String?, onScreenOnly: Bool) -> [SCWindow] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [SCWindow] = []

        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreenOnly)
                result = content.windows.filter { window in
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
                result = []
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }
}
