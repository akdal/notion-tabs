import AppKit
import Foundation
import SwiftUI

@main
struct NotionTabsUIApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Notion Tabs UI", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 640)
        }
        MenuBarExtra("Notion Tabs", systemImage: "square.stack.3d.up") {
            MenuBarMenuContent(viewModel: viewModel) {
                openWindow(id: "main")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var windows: [UIWindowSnapshot] = []
    @Published var focusedTitle: String = "<none>"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastStrategy: String = "-"
    @Published var lastElapsedMS: Int = 0
    @Published var debugRawJSON: String = ""
    @Published var searchQuery: String = ""
    @Published var autoRefreshEnabled = false
    @Published var actionHistory: [ActionLog] = []

    private let client = NotionTabsCLIClient()
    private var autoRefreshTask: Task<Void, Never>?

    func refresh() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.list()
                self.focusedTitle = result.payload.focusedTitle ?? "<none>"
                self.windows = result.payload.windows
                self.lastElapsedMS = result.elapsedMS
                self.debugRawJSON = result.rawJSON
                self.errorMessage = nil
            } catch let error as CLIErrorEnvelope {
                self.errorMessage = "[\(error.error.code)] \(error.error.message)"
                self.debugRawJSON = error.rawJSON ?? ""
                self.record(action: "refresh", strategy: "-", message: self.errorMessage ?? "error")
            } catch {
                self.errorMessage = String(describing: error)
                self.record(action: "refresh", strategy: "-", message: self.errorMessage ?? "error")
            }
        }
    }

    func focusWindow(index: Int) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.focusWindow(window: String(index))
                self.lastStrategy = result.payload.strategy ?? "-"
                self.lastElapsedMS = result.elapsedMS
                self.debugRawJSON = result.rawJSON
                self.errorMessage = nil
                self.record(
                    action: "focus-window \(index)",
                    strategy: result.payload.strategy ?? "-",
                    message: "\(result.payload.message) (\(result.elapsedMS)ms)"
                )
                try await self.reloadListOnly()
            } catch let error as CLIErrorEnvelope {
                self.errorMessage = "[\(error.error.code)] \(error.error.message)"
                self.debugRawJSON = error.rawJSON ?? ""
                self.record(action: "focus-window \(index)", strategy: "-", message: self.errorMessage ?? "error")
            } catch {
                self.errorMessage = String(describing: error)
                self.record(action: "focus-window \(index)", strategy: "-", message: self.errorMessage ?? "error")
            }
        }
    }

    func focusTab(window: Int, tab: Int) {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.focusTab(window: String(window), tab: String(tab))
                self.lastStrategy = result.payload.strategy ?? "-"
                self.lastElapsedMS = result.elapsedMS
                self.debugRawJSON = result.rawJSON
                self.errorMessage = nil
                self.record(
                    action: "focus-tab w\(window) t\(tab)",
                    strategy: result.payload.strategy ?? "-",
                    message: "\(result.payload.message) (\(result.elapsedMS)ms)"
                )
                try await self.reloadListOnly()
            } catch let error as CLIErrorEnvelope {
                self.errorMessage = "[\(error.error.code)] \(error.error.message)"
                self.debugRawJSON = error.rawJSON ?? ""
                self.record(action: "focus-tab w\(window) t\(tab)", strategy: "-", message: self.errorMessage ?? "error")
            } catch {
                self.errorMessage = String(describing: error)
                self.record(action: "focus-tab w\(window) t\(tab)", strategy: "-", message: self.errorMessage ?? "error")
            }
        }
    }

    func setAutoRefresh(enabled: Bool) {
        autoRefreshEnabled = enabled
        autoRefreshTask?.cancel()
        guard enabled else { return }
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        autoRefreshEnabled = false
    }

    private func reloadListOnly() async throws {
        let listResult = try await client.list()
        focusedTitle = listResult.payload.focusedTitle ?? "<none>"
        windows = listResult.payload.windows
    }

    private func record(action: String, strategy: String, message: String) {
        actionHistory.insert(
            ActionLog(timestamp: Date(), action: action, strategy: strategy, message: message),
            at: 0
        )
        if actionHistory.count > 20 {
            actionHistory.removeLast(actionHistory.count - 20)
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    private var filteredWindows: [FilteredWindow] {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return viewModel.windows.map { FilteredWindow(window: $0, tabs: $0.tabs) }
        }
        return viewModel.windows.compactMap { window in
            let windowMatch = window.persistedActiveTitle.lowercased().contains(query)
            let tabMatches = window.tabs.filter { $0.title.lowercased().contains(query) }
            if windowMatch { return FilteredWindow(window: window, tabs: window.tabs) }
            if !tabMatches.isEmpty { return FilteredWindow(window: window, tabs: tabMatches) }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notion Tabs")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Focused: \(viewModel.focusedTitle)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Strategy: \(viewModel.lastStrategy)")
                    .foregroundStyle(.secondary)
                Text("Elapsed: \(viewModel.lastElapsedMS)ms")
                    .foregroundStyle(.secondary)
                Button("Refresh") { viewModel.refresh() }
                    .disabled(viewModel.isLoading)
            }

            HStack {
                TextField("Search windows/tabs", text: $viewModel.searchQuery)
                Toggle("Auto Refresh (2s)", isOn: Binding(
                    get: { viewModel.autoRefreshEnabled },
                    set: { viewModel.setAutoRefresh(enabled: $0) }
                ))
                .fixedSize()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(alignment: .top, spacing: 12) {
                List {
                    ForEach(filteredWindows) { item in
                        Section {
                            ForEach(item.tabs) { tab in
                                HStack {
                                    Text("[\(tab.index)] \(tab.title)")
                                        .lineLimit(1)
                                    Spacer()
                                    if tab.isAXFocused {
                                        Text("Now").foregroundStyle(.blue)
                                    } else if tab.isPersistedActive {
                                        Text("State").foregroundStyle(.orange)
                                    }
                                    Button("Focus") {
                                        viewModel.focusTab(window: item.window.index, tab: tab.index)
                                    }
                                    .disabled(viewModel.isLoading)
                                }
                            }
                        } header: {
                            HStack {
                                Text("[\(item.window.index)] \(item.window.persistedActiveTitle)")
                                Spacer()
                                if item.window.isAXFocused {
                                    Text("Focused").foregroundStyle(.blue)
                                }
                                Button("Focus Window") {
                                    viewModel.focusWindow(index: item.window.index)
                                }
                                .disabled(viewModel.isLoading)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Actions")
                        .font(.headline)
                    List(viewModel.actionHistory) { row in
                        ActionHistoryRow(row: row)
                    }
                    .frame(height: 180)

                    Text("Debug JSON")
                        .font(.headline)
                    ScrollView {
                        Text(viewModel.debugRawJSON)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 340)
            }
        }
        .padding(14)
        .onAppear { viewModel.refresh() }
        .onDisappear { viewModel.stopAutoRefresh() }
    }
}

struct ActionHistoryRow: View {
    let row: ActionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(row.timestamp.formatted(date: .omitted, time: .standard)) • \(row.strategy)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(row.action)
            Text(row.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct MenuBarMenuContent: View {
    @ObservedObject var viewModel: AppViewModel
    let onOpenMainWindow: () -> Void

    var body: some View {
        Group {
            Button("Refresh") { viewModel.refresh() }
            Button("Open Main Window") { onOpenMainWindow() }
            Toggle("Auto Refresh (2s)", isOn: Binding(
                get: { viewModel.autoRefreshEnabled },
                set: { viewModel.setAutoRefresh(enabled: $0) }
            ))
            Divider()
            ForEach(viewModel.windows) { window in
                Menu("[\(window.index)] \(window.persistedActiveTitle)") {
                    Button("Focus Window") { viewModel.focusWindow(index: window.index) }
                    Divider()
                    ForEach(window.tabs) { tab in
                        Button("[\(tab.index)] \(tab.title)") {
                            viewModel.focusTab(window: window.index, tab: tab.index)
                        }
                    }
                }
            }
            if let error = viewModel.errorMessage {
                Divider()
                Text(error)
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .onAppear {
            if viewModel.windows.isEmpty {
                viewModel.refresh()
            }
        }
    }
}

struct FilteredWindow: Identifiable {
    let window: UIWindowSnapshot
    let tabs: [UITabSnapshot]
    var id: String { window.id }
}

struct ActionLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: String
    let strategy: String
    let message: String
}

struct UIWindowSnapshot: Identifiable, Decodable {
    let id: String
    let index: Int
    let persistedActiveTitle: String
    let isAXFocused: Bool
    let tabs: [UITabSnapshot]
}

struct UITabSnapshot: Identifiable, Decodable {
    let id: String
    let index: Int
    let title: String
    let isPersistedActive: Bool
    let isAXFocused: Bool
}

struct ListPayload: Decodable {
    let success: Bool
    let focusedTitle: String?
    let windows: [UIWindowSnapshot]
}

struct FocusPayload: Decodable {
    let success: Bool
    let targetTitle: String
    let focusedTitle: String?
    let strategy: String?
    let message: String
}

struct CLIErrorBody: Decodable {
    let code: String
    let message: String
}

struct CLIErrorEnvelope: Error, Decodable {
    let success: Bool
    let error: CLIErrorBody
    var rawJSON: String?
}

struct InvocationResult<Payload> {
    let payload: Payload
    let rawJSON: String
    let elapsedMS: Int
}

struct NotionTabsCLIClient {
    func list() async throws -> InvocationResult<ListPayload> {
        try await invoke(["list", "--json"], as: ListPayload.self)
    }

    func focusWindow(window: String) async throws -> InvocationResult<FocusPayload> {
        try await invoke(["focus-window", "--window", window, "--json"], as: FocusPayload.self)
    }

    func focusTab(window: String, tab: String) async throws -> InvocationResult<FocusPayload> {
        try await invoke(["focus-tab", "--window", window, "--tab", tab, "--json"], as: FocusPayload.self)
    }

    private func invoke<T: Decodable>(_ args: [String], as type: T.Type) async throws -> InvocationResult<T> {
        let start = Date()
        let output = try await runProcess(args: args)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(T.self, from: output.data) {
            return InvocationResult(payload: payload, rawJSON: output.text, elapsedMS: elapsed)
        }

        if var err = try? decoder.decode(CLIErrorEnvelope.self, from: output.data) {
            err.rawJSON = output.text
            throw err
        }

        throw NSError(domain: "notion-tabs-ui", code: Int(output.exitCode), userInfo: [
            NSLocalizedDescriptionKey: output.text.isEmpty ? "Unknown CLI output." : output.text
        ])
    }

    private func runProcess(args: [String]) async throws -> (data: Data, text: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            if let bin = binaryPath() {
                process.executableURL = URL(fileURLWithPath: bin)
                process.arguments = args
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["swift", "run", "notion-tabs"] + args
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { p in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let merged = outData.isEmpty ? errData : outData
                let text = String(data: merged, encoding: .utf8) ?? ""
                continuation.resume(returning: (merged, text, p.terminationStatus))
            }
        }
    }

    private func binaryPath() -> String? {
        if let env = ProcessInfo.processInfo.environment["NOTION_TABS_BIN"], FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        let cwd = FileManager.default.currentDirectoryPath
        let candidate = "\(cwd)/.build/debug/notion-tabs"
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }
}
