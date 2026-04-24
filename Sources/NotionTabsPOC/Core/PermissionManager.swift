import ApplicationServices
import Foundation

struct PermissionManager {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermissionPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
