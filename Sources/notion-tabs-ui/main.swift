import AppKit
import ApplicationServices
import Foundation
import NotionTabsCore
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
    @Published var appStatus = AppStatus()
    @Published var logPath: String = UILogger.shared.fileURL.path
    @Published var lastRefreshAt: Date?

    private let client = NotionTabsCLIClient()
    private var autoRefreshTask: Task<Void, Never>?
    private var lastListSignature: String?
    private var workspaceObservers: [NSObjectProtocol] = []

    func refresh() {
        updateRuntimeStatus()
        isLoading = true
        UILogger.shared.write("ui refresh requested")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            guard self.appStatus.notionRunning else {
                self.errorMessage = "Notion is not running"
                self.lastStrategy = "-"
                self.lastElapsedMS = 0
                self.debugRawJSON = ""
                UILogger.shared.write("ui refresh skipped notion-not-running")
                return
            }
            do {
                let result = try await self.client.list()
                self.applyListResult(result)
                self.errorMessage = nil
                UILogger.shared.write("ui refresh success windows=\(result.payload.windows.count) elapsedMS=\(result.elapsedMS)")
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

    func focusWindow(_ window: UIWindowSnapshot) {
        updateRuntimeStatus()
        isLoading = true
        let target = window.id
        let label = "[\(window.index)] \(window.persistedActiveTitle)"
        UILogger.shared.write("ui focus-window requested label='\(label)' windowID=\(target)")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.focusWindow(window: target)
                self.lastStrategy = result.payload.strategy ?? "-"
                self.lastElapsedMS = result.elapsedMS
                self.debugRawJSON = result.rawJSON
                self.errorMessage = nil
                self.record(
                    action: "focus-window \(label)",
                    strategy: result.payload.strategy ?? "-",
                    message: "\(result.payload.message) (\(result.elapsedMS)ms)"
                )
                try await self.reloadListOnly()
            } catch let error as CLIErrorEnvelope {
                self.errorMessage = "[\(error.error.code)] \(error.error.message)"
                self.debugRawJSON = error.rawJSON ?? ""
                self.record(action: "focus-window \(label)", strategy: "-", message: self.errorMessage ?? "error")
            } catch {
                self.errorMessage = String(describing: error)
                self.record(action: "focus-window \(label)", strategy: "-", message: self.errorMessage ?? "error")
            }
        }
    }

    func focusTab(window: UIWindowSnapshot, tab: UITabSnapshot) {
        updateRuntimeStatus()
        isLoading = true
        let windowTarget = window.id
        let tabTarget = tab.id
        let label = "w\(window.index) '\(window.persistedActiveTitle)' t\(tab.index) '\(tab.title)'"
        UILogger.shared.write("ui focus-tab requested label='\(label)' windowID=\(windowTarget) tabID=\(tabTarget)")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let result = try await self.client.focusTab(window: windowTarget, tab: tabTarget)
                self.lastStrategy = result.payload.strategy ?? "-"
                self.lastElapsedMS = result.elapsedMS
                self.debugRawJSON = result.rawJSON
                self.errorMessage = nil
                self.record(
                    action: "focus-tab \(label)",
                    strategy: result.payload.strategy ?? "-",
                    message: "\(result.payload.message) (\(result.elapsedMS)ms)"
                )
                try await self.reloadListOnly()
            } catch let error as CLIErrorEnvelope {
                self.errorMessage = "[\(error.error.code)] \(error.error.message)"
                self.debugRawJSON = error.rawJSON ?? ""
                self.record(action: "focus-tab \(label)", strategy: "-", message: self.errorMessage ?? "error")
            } catch {
                self.errorMessage = String(describing: error)
                self.record(action: "focus-tab \(label)", strategy: "-", message: self.errorMessage ?? "error")
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
                if Task.isCancelled { break }
                self.updateRuntimeStatus()
                if self.appStatus.notionRunning {
                    self.refresh()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        autoRefreshEnabled = false
    }

    func startLifecycleObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "notion.id" || app.bundleIdentifier == "com.notion.id"
            else { return }
            Task { @MainActor in
                self?.updateRuntimeStatus()
                self?.refresh()
            }
        }
        let terminate = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "notion.id" || app.bundleIdentifier == "com.notion.id"
            else { return }
            Task { @MainActor in
                self?.updateRuntimeStatus()
                self?.windows = []
                self?.focusedTitle = "<none>"
                self?.debugRawJSON = ""
                self?.errorMessage = "Notion is not running"
            }
        }
        workspaceObservers = [launch, terminate]
    }

    func stopLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateRuntimeStatus()
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(UILogger.shared.directoryURL)
    }

    func updateRuntimeStatus() {
        appStatus = AppStatus(
            notionRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: "notion.id").isEmpty,
            accessibilityTrusted: AXIsProcessTrusted(),
            cliPath: client.availableBinaryPath()
        )
    }

    private func reloadListOnly() async throws {
        let listResult = try await client.list()
        applyListResult(listResult)
    }

    private func record(action: String, strategy: String, message: String) {
        UILogger.shared.write("ui action action='\(action)' strategy='\(strategy)' message='\(message)'")
        actionHistory.insert(
            ActionLog(timestamp: Date(), action: action, strategy: strategy, message: message),
            at: 0
        )
        if actionHistory.count > 20 {
            actionHistory.removeLast(actionHistory.count - 20)
        }
    }

    private func applyListResult(_ result: InvocationResult<ListPayload>) {
        let signature = listSignature(for: result.payload)
        lastElapsedMS = result.elapsedMS
        focusedTitle = result.payload.focusedTitle ?? "<none>"
        lastRefreshAt = Date()
        if signature == lastListSignature {
            UILogger.shared.write("ui list unchanged signature=\(signature)")
            return
        }
        lastListSignature = signature
        windows = result.payload.windows
        debugRawJSON = result.rawJSON
    }

    private func listSignature(for payload: ListPayload) -> String {
        let focused = payload.focusedTitle ?? "<none>"
        let windows = payload.windows.map { window in
            let tabs = window.tabs.map { tab in
                "\(tab.id)|\(tab.index)|\(tab.title)|\(tab.isPersistedActive)|\(tab.isAXFocused)"
            }.joined(separator: ";")
            return "\(window.id)|\(window.index)|\(window.persistedActiveTitle)|\(window.isAXFocused)|\(window.isInWindowMenu)|\(tabs)"
        }.joined(separator: "||")
        return "\(focused)###\(windows)"
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
                    Text(viewModel.lastRefreshAt?.formatted(date: .omitted, time: .standard) ?? "Not refreshed yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Strategy: \(viewModel.lastStrategy)")
                    .foregroundStyle(.secondary)
                Text("Elapsed: \(viewModel.lastElapsedMS)ms")
                    .foregroundStyle(.secondary)
                Button("Refresh") { viewModel.refresh() }
                    .disabled(viewModel.isLoading)
            }

            StatusBar(status: viewModel.appStatus) {
                viewModel.requestAccessibilityPermission()
            }

            HStack {
                TextField("Search windows/tabs", text: $viewModel.searchQuery)
                Toggle("Auto Refresh (2s)", isOn: Binding(
                    get: { viewModel.autoRefreshEnabled },
                    set: { viewModel.setAutoRefresh(enabled: $0) }
                ))
                .fixedSize()
                Text(viewModel.appStatus.notionRunning ? "Auto refresh active" : "Auto refresh paused: Notion off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                                        Text("Focused").foregroundStyle(.blue)
                                    } else if tab.isPersistedActive {
                                        Text("State").foregroundStyle(.orange)
                                    }
                                    Button("Focus") {
                                        viewModel.focusTab(window: item.window, tab: tab)
                                    }
                                    .disabled(viewModel.isLoading || !item.window.isActionable)
                                }
                                .font(tab.isAXFocused ? .body.weight(.semibold) : .body)
                                .padding(.vertical, 2)
                                .listRowBackground(tab.isAXFocused ? Color.accentColor.opacity(0.14) : Color.clear)
                            }
                        } header: {
                            HStack {
                                Text("[\(item.window.index)] \(item.window.persistedActiveTitle)")
                                Spacer()
                                if item.window.isAXFocused {
                                    Text("Focused").foregroundStyle(.blue)
                                }
                                if let focusedTab = item.window.tabs.first(where: { $0.isAXFocused }) {
                                    Text(focusedTab.title)
                                        .foregroundStyle(item.window.isAXFocused ? .blue : .secondary)
                                        .lineLimit(1)
                                }
                                Button("Focus Window") {
                                    viewModel.focusWindow(item.window)
                                }
                                .disabled(viewModel.isLoading || !item.window.isActionable)
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
                    HStack {
                        Text(viewModel.logPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Logs") { viewModel.openLogsFolder() }
                    }
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
        .onAppear {
            viewModel.startLifecycleObservers()
            viewModel.updateRuntimeStatus()
            viewModel.refresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
            viewModel.stopLifecycleObservers()
        }
    }
}

struct StatusBar: View {
    let status: AppStatus
    let requestAccessibility: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(status.notionRunning ? "Notion Running" : "Notion Not Running", systemImage: status.notionRunning ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(status.notionRunning ? .green : .red)
            Label(status.accessibilityTrusted ? "Accessibility Granted" : "Accessibility Required", systemImage: status.accessibilityTrusted ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(status.accessibilityTrusted ? .green : .orange)
            Label(status.cliPath == nil ? "CLI Missing" : "CLI Ready", systemImage: status.cliPath == nil ? "xmark.circle" : "checkmark.circle")
                .foregroundStyle(status.cliPath == nil ? .red : .green)
            Spacer()
            if !status.accessibilityTrusted {
                Button("Grant Accessibility", action: requestAccessibility)
            }
        }
        .font(.caption)
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
            Text(viewModel.appStatus.menuSummary)
            Divider()
            Button("Refresh") { viewModel.refresh() }
            Button("Open Main Window") { onOpenMainWindow() }
            Button("Open Logs Folder") { viewModel.openLogsFolder() }
            if !viewModel.appStatus.accessibilityTrusted {
                Button("Grant Accessibility") { viewModel.requestAccessibilityPermission() }
            }
            Toggle("Auto Refresh (2s)", isOn: Binding(
                get: { viewModel.autoRefreshEnabled },
                set: { viewModel.setAutoRefresh(enabled: $0) }
            ))
            Text(viewModel.appStatus.notionRunning ? "Auto refresh active" : "Auto refresh paused: Notion off")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(viewModel.windows) { window in
                Menu("[\(window.index)] \(window.persistedActiveTitle)") {
                    Button("Focus Window") { viewModel.focusWindow(window) }
                        .disabled(!window.isActionable)
                    Divider()
                    ForEach(window.tabs) { tab in
                        Button("[\(tab.index)] \(tab.title)") {
                            viewModel.focusTab(window: window, tab: tab)
                        }
                        .disabled(!window.isActionable)
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
            viewModel.startLifecycleObservers()
            viewModel.updateRuntimeStatus()
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

struct AppStatus {
    var notionRunning = false
    var accessibilityTrusted = false
    var cliPath: String?

    var menuSummary: String {
        let notion = notionRunning ? "Notion: Running" : "Notion: Not Running"
        let accessibility = accessibilityTrusted ? "AX: Granted" : "AX: Required"
        let cli = cliPath == nil ? "CLI: Missing" : "CLI: Ready"
        return "\(notion) / \(accessibility) / \(cli)"
    }
}

struct UIWindowSnapshot: Identifiable, Decodable {
    let id: String
    let index: Int
    let persistedActiveTitle: String
    let isAXFocused: Bool
    let isInWindowMenu: Bool
    let tabs: [UITabSnapshot]

    var isActionable: Bool {
        true
    }

    init(
        id: String,
        index: Int,
        persistedActiveTitle: String,
        isAXFocused: Bool,
        isInWindowMenu: Bool,
        tabs: [UITabSnapshot]
    ) {
        self.id = id
        self.index = index
        self.persistedActiveTitle = persistedActiveTitle
        self.isAXFocused = isAXFocused
        self.isInWindowMenu = isInWindowMenu
        self.tabs = tabs
    }

    init(snapshot: WindowSnapshot) {
        self.init(
            id: snapshot.id,
            index: snapshot.index,
            persistedActiveTitle: snapshot.persistedActiveTitle,
            isAXFocused: snapshot.isAXFocused,
            isInWindowMenu: snapshot.isInWindowMenu,
            tabs: snapshot.tabs.map(UITabSnapshot.init(snapshot:))
        )
    }
}

struct UITabSnapshot: Identifiable, Decodable {
    let id: String
    let index: Int
    let title: String
    let isPersistedActive: Bool
    let isAXFocused: Bool

    init(id: String, index: Int, title: String, isPersistedActive: Bool, isAXFocused: Bool) {
        self.id = id
        self.index = index
        self.title = title
        self.isPersistedActive = isPersistedActive
        self.isAXFocused = isAXFocused
    }

    init(snapshot: TabSnapshot) {
        self.init(
            id: snapshot.id,
            index: snapshot.index,
            title: snapshot.title,
            isPersistedActive: snapshot.isPersistedActive,
            isAXFocused: snapshot.isAXFocused
        )
    }
}

struct ListPayload: Decodable {
    let success: Bool
    let focusedTitle: String?
    let windows: [UIWindowSnapshot]

    init(success: Bool, focusedTitle: String?, windows: [UIWindowSnapshot]) {
        self.success = success
        self.focusedTitle = focusedTitle
        self.windows = windows
    }

    init(snapshot: ListSnapshot) {
        self.init(
            success: true,
            focusedTitle: snapshot.focusedTitle,
            windows: snapshot.windows.map(UIWindowSnapshot.init(snapshot:))
        )
    }
}

struct FocusPayload: Decodable {
    let success: Bool
    let targetTitle: String
    let focusedTitle: String?
    let strategy: String?
    let message: String

    init(success: Bool, targetTitle: String, focusedTitle: String?, strategy: String?, message: String) {
        self.success = success
        self.targetTitle = targetTitle
        self.focusedTitle = focusedTitle
        self.strategy = strategy
        self.message = message
    }

    init(result: FocusResult) {
        self.init(
            success: result.success,
            targetTitle: result.targetTitle,
            focusedTitle: result.focusedTitle,
            strategy: result.strategy,
            message: result.message
        )
    }
}

struct CLIErrorBody: Decodable {
    let code: String
    let message: String

    init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

struct CLIErrorEnvelope: Error, Decodable {
    let success: Bool
    let error: CLIErrorBody
    var rawJSON: String?

    init(success: Bool = false, error: CLIErrorBody, rawJSON: String?) {
        self.success = success
        self.error = error
        self.rawJSON = rawJSON
    }

    init(error source: Error, rawJSON: String?) {
        if let domain = source as? NotionTabsError {
            self.init(
                error: CLIErrorBody(code: domain.code, message: domain.errorDescription ?? String(describing: domain)),
                rawJSON: rawJSON
            )
            return
        }
        if let localized = source as? LocalizedError, let description = localized.errorDescription {
            self.init(error: CLIErrorBody(code: "UNKNOWN_ERROR", message: description), rawJSON: rawJSON)
            return
        }
        self.init(error: CLIErrorBody(code: "UNKNOWN_ERROR", message: String(describing: source)), rawJSON: rawJSON)
    }
}

struct InvocationResult<Payload> {
    let payload: Payload
    let rawJSON: String
    let elapsedMS: Int
}

final class UILogger {
    static let shared = UILogger()

    let directoryURL: URL
    let fileURL: URL

    private let queue = DispatchQueue(label: "notion-tabs-ui.logger")
    private let formatter = ISO8601DateFormatter()

    private init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        directoryURL = libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Notion Tabs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        fileURL = directoryURL.appendingPathComponent("\(stampFormatter.string(from: Date()))-ui.log")
        write("ui logger started file=\(fileURL.path)")
    }

    func write(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            do {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    let handle = try FileHandle(forWritingTo: self.fileURL)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try handle.close()
                } else {
                    try data.write(to: self.fileURL)
                }
            } catch {
                NSLog("notion-tabs-ui log write failed: \(String(describing: error))")
            }
        }
    }
}

struct NotionTabsCLIClient {
    func list() async throws -> InvocationResult<ListPayload> {
        try await invoke(action: "list") {
            let snapshot = try NotionTabsService().listWindows()
            let payload = ListPayload(snapshot: snapshot)
            return (payload, listJSON(snapshot))
        }
    }

    func focusWindow(window: String) async throws -> InvocationResult<FocusPayload> {
        try await invoke(action: "focus-window --window \(window)") {
            let result = try NotionTabsService().focusWindow(WindowRef(window))
            let payload = FocusPayload(result: result)
            return (payload, focusJSON(result))
        }
    }

    func focusTab(window: String, tab: String) async throws -> InvocationResult<FocusPayload> {
        try await invoke(action: "focus-tab --window \(window) --tab \(tab)") {
            let result = try NotionTabsService().focusTab(window: WindowRef(window), tab: TabRef(tab))
            let payload = FocusPayload(result: result)
            return (payload, focusJSON(result))
        }
    }

    private func invoke<T>(action: String, operation: @escaping @Sendable () throws -> (T, [String: Any])) async throws -> InvocationResult<T> {
        let start = Date()
        UILogger.shared.write("core start action=\(action)")
        do {
            let (payload, json) = try await Task.detached(priority: .userInitiated) {
                try operation()
            }.value
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let rawJSON = renderJSON(json)
            UILogger.shared.write("core finish elapsedMS=\(elapsed) action=\(action) output=\(rawJSON)")
            return InvocationResult(payload: payload, rawJSON: rawJSON, elapsedMS: elapsed)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let rawJSON = renderJSON(errorJSON(error))
            UILogger.shared.write("core fail elapsedMS=\(elapsed) action=\(action) output=\(rawJSON)")
            throw CLIErrorEnvelope(error: error, rawJSON: rawJSON)
        }
    }

    func availableBinaryPath() -> String? {
        "embedded-core"
    }
}

private func renderJSON(_ payload: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{\"success\":false,\"error\":{\"code\":\"JSON_SERIALIZATION_FAILED\",\"message\":\"Failed to render JSON.\"}}"
    }
    return text
}

private func listJSON(_ snapshot: ListSnapshot) -> [String: Any] {
    [
        "success": true,
        "focusedTitle": snapshot.focusedTitle as Any,
        "state": [
            "path": snapshot.statePath,
            "modifiedAt": snapshot.stateModifiedAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
        ],
        "windows": snapshot.windows.map { window in
            [
                "id": window.id,
                "index": window.index,
                "persistedActiveTitle": window.persistedActiveTitle,
                "isAXFocused": window.isAXFocused,
                "isInWindowMenu": window.isInWindowMenu,
                "frame": [
                    "x": window.frame.x,
                    "y": window.frame.y,
                    "width": window.frame.width,
                    "height": window.frame.height,
                ],
                "tabs": window.tabs.map { tab in
                    [
                        "id": tab.id,
                        "index": tab.index,
                        "title": tab.title,
                        "isPersistedActive": tab.isPersistedActive,
                        "isAXFocused": tab.isAXFocused,
                    ]
                },
            ]
        },
    ]
}

private func focusJSON(_ result: FocusResult) -> [String: Any] {
    [
        "success": result.success,
        "targetTitle": result.targetTitle,
        "focusedTitle": result.focusedTitle as Any,
        "strategy": result.strategy as Any,
        "message": result.message,
    ]
}

private func errorJSON(_ error: Error) -> [String: Any] {
    if let domain = error as? NotionTabsError {
        return [
            "success": false,
            "error": [
                "code": domain.code,
                "message": domain.errorDescription ?? String(describing: domain),
            ],
        ]
    }

    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return [
            "success": false,
            "error": [
                "code": "UNKNOWN_ERROR",
                "message": description,
            ],
        ]
    }

    return [
        "success": false,
        "error": [
            "code": "UNKNOWN_ERROR",
            "message": String(describing: error),
        ],
    ]
}
