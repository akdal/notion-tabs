import AppKit
import Foundation

struct NotionAppInstance {
    let runningApplication: NSRunningApplication
    let bundleIdentifier: String?

    var pid: pid_t { runningApplication.processIdentifier }
    var localizedName: String { runningApplication.localizedName ?? "Notion" }
}

struct NotionAppLocator {
    private static let candidateBundleIDs = [
        "notion.id",
        "com.notion.id",
    ]

    func findRunningNotion() -> NotionAppInstance? {
        for bundleID in Self.candidateBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return NotionAppInstance(runningApplication: app, bundleIdentifier: app.bundleIdentifier)
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return Self.candidateBundleIDs.contains(bundleID)
        }) {
            return NotionAppInstance(runningApplication: app, bundleIdentifier: app.bundleIdentifier)
        }

        return nil
    }
}
