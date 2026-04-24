import AppKit
import Foundation

struct AppActivationService {
    @discardableResult
    func activate(_ app: NSRunningApplication) -> Bool {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
