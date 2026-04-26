import AppKit
import Foundation

struct ProcessSource {
    private let bundleIDs = ["notion.id", "com.notion.id"]

    func find() -> (record: ProcessRecord, app: NSRunningApplication?) {
        let apps = NSWorkspace.shared.runningApplications
        let app = apps.first { running in
            guard let bundleID = running.bundleIdentifier else { return false }
            return bundleIDs.contains(bundleID)
        }

        guard let app else {
            return (ProcessRecord(found: false, pid: nil, bundleIdentifier: nil, localizedName: nil, isActive: nil, isHidden: nil), nil)
        }

        return (
            ProcessRecord(
                found: true,
                pid: Int(app.processIdentifier),
                bundleIdentifier: app.bundleIdentifier,
                localizedName: app.localizedName,
                isActive: app.isActive,
                isHidden: app.isHidden
            ),
            app
        )
    }
}

