import Foundation

enum Logger {
    static func info(_ message: String) {
        fputs("[INFO] \(message)\n", stdout)
    }

    static func warn(_ message: String) {
        fputs("[WARN] \(message)\n", stderr)
    }

    static func error(_ message: String) {
        fputs("[ERROR] \(message)\n", stderr)
    }
}
