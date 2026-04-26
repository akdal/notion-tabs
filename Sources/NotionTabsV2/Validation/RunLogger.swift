import Foundation

struct RunEvent: Codable {
    let timestamp: String
    let phase: Phase
    let step: String
    let status: Verdict
    let elapsedMS: Int
    let message: String
    let evidence: JSONValue
}

final class RunLogger {
    let commandName: String
    let startedAtDate = Date()
    let runDirectory: URL

    private let encoder: JSONEncoder
    private let eventEncoder: JSONEncoder
    private var events: [RunEvent] = []
    private var sourcePayloads: [String: JSONValue] = [:]

    init(commandName: String) {
        self.commandName = commandName
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.eventEncoder = JSONEncoder()
        self.eventEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let stamp = Self.pathStampFormatter.string(from: startedAtDate)
        let safeName = commandName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        self.runDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("logs/v2/\(stamp)-\(safeName)-\(suffix)")

        try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    }

    func event(phase: Phase, step: String, status: Verdict, message: String, evidence: JSONValue = .object([:])) {
        let elapsed = Int(Date().timeIntervalSince(startedAtDate) * 1000)
        let event = RunEvent(
            timestamp: Self.isoFormatter.string(from: Date()),
            phase: phase,
            step: step,
            status: status,
            elapsedMS: elapsed,
            message: message,
            evidence: evidence
        )
        events.append(event)
        print("[\(status.rawValue)] \(step): \(message)")
    }

    func recordSource(name: String, payload: JSONValue) {
        sourcePayloads[name] = payload
    }

    func writeText(_ text: String, to filename: String) {
        try? text.write(to: runDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    func finish(verdict: Verdict, failedAssumption: String?, summary: String, counts: [String: Int] = [:]) -> Int32 {
        let result = CommandResult(
            command: commandName,
            scenario: nil,
            startedAt: Self.isoFormatter.string(from: startedAtDate),
            endedAt: Self.isoFormatter.string(from: Date()),
            verdict: verdict,
            failedAssumption: failedAssumption,
            summary: summary,
            counts: counts
        )

        writeEvents()
        writeJSON(sourcePayloads, to: "sources.json")
        writeJSON(result, to: "result.json")
        writeSummary(result)

        print("logDir=\(runDirectory.path)")
        return verdict.exitCode
    }

    private func writeEvents() {
        let url = runDirectory.appendingPathComponent("events.jsonl")
        let lines = events.compactMap { event -> String? in
            guard let data = try? eventEncoder.encode(event) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON<T: Encodable>(_ value: T, to filename: String) {
        let url = runDirectory.appendingPathComponent(filename)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func writeSummary(_ result: CommandResult) {
        let text = """
        # V2 Run Summary

        - command: \(result.command)
        - verdict: \(result.verdict.rawValue)
        - failedAssumption: \(result.failedAssumption ?? "<none>")
        - summary: \(result.summary)
        - startedAt: \(result.startedAt)
        - endedAt: \(result.endedAt)

        ## Counts

        \(result.counts.sorted(by: { $0.key < $1.key }).map { "- \($0.key): \($0.value)" }.joined(separator: "\n"))

        """
        try? text.write(to: runDirectory.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let pathStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
