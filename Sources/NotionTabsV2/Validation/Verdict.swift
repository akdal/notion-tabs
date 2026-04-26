import Foundation

enum Verdict: String, Codable {
    case pass
    case softPass = "soft_pass"
    case fail
    case blocked
    case ambiguous
    case info

    var exitCode: Int32 {
        switch self {
        case .pass, .softPass, .info: return 0
        case .fail: return 1
        case .blocked: return 2
        case .ambiguous: return 3
        }
    }
}

enum Phase: String, Codable {
    case source
    case bridge
    case action
    case confirm
    case environment
}

struct CommandResult: Codable {
    let command: String
    let scenario: String?
    let startedAt: String
    let endedAt: String
    let verdict: Verdict
    let failedAssumption: String?
    let summary: String
    let counts: [String: Int]
}

