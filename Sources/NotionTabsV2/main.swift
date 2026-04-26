import ApplicationServices
import AppKit
import Foundation

enum V2Command {
    case help
    case list
    case userFocusWindow(windowID: String, timeoutMS: Int)
    case userFocusTab(windowID: String, tabID: String?, tabTitle: String?, timeoutMS: Int)
    case env
    case sourcePersisted
    case sourceLiveWindows
    case sourceAXWindows
    case sourceFocusedWindow
    case sourceFocusDiagnostics
    case sourceWindowMenu
    case sourceFocusedTabs(strict: Bool)
    case sourceFocusedTabWebAreas
    case sourceFocusedAXTree(depth: Int)
    case sourcePointDiagnostics(x: Int, y: Int)
    case sourcePersistedWatch(duration: Int, thresholdMS: Int)
    case sourceSampleState(samples: Int, intervalMS: Int)
    case bridgeWindows
    case bridgeMenu
    case bridgeFocusedWindow(windowID: String)
    case bridgeFocusedTabs(windowID: String)
    case bridgeTabObservation(windowID: String)
    case actionFocusWindow(windowID: String, strategy: FocusStrategy, timeoutMS: Int)
    case actionFocusTab(windowID: String, tabID: String?, tabTitle: String?, strategy: FocusTabStrategy, timeoutMS: Int)
}

struct V2CommandParser {
    static func parse(_ arguments: [String]) -> V2Command {
        guard arguments.count >= 2 else { return .help }
        if arguments[1] == "env" { return .env }
        switch arguments[1] {
        case "list":
            return .list
        case "focus-window":
            guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
            return .userFocusWindow(windowID: windowID, timeoutMS: intFlag(arguments, "--timeout-ms") ?? 2000)
        case "focus-tab":
            guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
            return .userFocusTab(
                windowID: windowID,
                tabID: stringFlag(arguments, "--tab-id"),
                tabTitle: stringFlag(arguments, "--tab-title"),
                timeoutMS: intFlag(arguments, "--timeout-ms") ?? 2500
            )
        case "source":
            guard arguments.count >= 3 else { return .help }
            switch arguments[2] {
            case "persisted":
                return .sourcePersisted
            case "persisted-watch":
                return .sourcePersistedWatch(
                    duration: intFlag(arguments, "--duration") ?? 30,
                    thresholdMS: intFlag(arguments, "--threshold-ms") ?? 2000
                )
            case "live-windows":
                return .sourceLiveWindows
            case "ax-windows":
                return .sourceAXWindows
            case "focused-window":
                return .sourceFocusedWindow
            case "focus-diagnostics":
                return .sourceFocusDiagnostics
            case "window-menu":
                return .sourceWindowMenu
            case "focused-tabs":
                return .sourceFocusedTabs(strict: !arguments.contains("--raw"))
            case "focused-tab-webareas":
                return .sourceFocusedTabWebAreas
            case "focused-ax-tree":
                return .sourceFocusedAXTree(depth: intFlag(arguments, "--depth") ?? 8)
            case "point-diagnostics":
                guard let x = intFlag(arguments, "--x"), let y = intFlag(arguments, "--y") else { return .help }
                return .sourcePointDiagnostics(x: x, y: y)
            case "sample-state":
                return .sourceSampleState(
                    samples: intFlag(arguments, "--samples") ?? 15,
                    intervalMS: intFlag(arguments, "--interval-ms") ?? 2000
                )
            default:
                return .help
            }
        case "bridge":
            guard arguments.count >= 3 else { return .help }
            switch arguments[2] {
            case "windows": return .bridgeWindows
            case "menu": return .bridgeMenu
            case "focused-window":
                guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
                return .bridgeFocusedWindow(windowID: windowID)
            case "focused-tabs":
                guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
                return .bridgeFocusedTabs(windowID: windowID)
            case "tab-observation":
                guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
                return .bridgeTabObservation(windowID: windowID)
            default: return .help
            }
        case "action":
            guard arguments.count >= 3 else { return .help }
            switch arguments[2] {
            case "focus-window":
                guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
                return .actionFocusWindow(
                    windowID: windowID,
                    strategy: strategyFlag(arguments) ?? .appFirst,
                    timeoutMS: intFlag(arguments, "--timeout-ms") ?? 1000
                )
            case "focus-tab":
                guard let windowID = stringFlag(arguments, "--window-id") else { return .help }
                return .actionFocusTab(
                    windowID: windowID,
                    tabID: stringFlag(arguments, "--tab-id"),
                    tabTitle: stringFlag(arguments, "--tab-title"),
                    strategy: tabStrategyFlag(arguments) ?? .pressOnly,
                    timeoutMS: intFlag(arguments, "--timeout-ms") ?? 1500
                )
            default:
                return .help
            }
        default:
            return .help
        }
    }

    private static func intFlag(_ arguments: [String], _ flag: String) -> Int? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Int(arguments[index + 1])
    }

    private static func stringFlag(_ arguments: [String], _ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func strategyFlag(_ arguments: [String]) -> FocusStrategy? {
        guard let value = stringFlag(arguments, "--strategy") else { return nil }
        return FocusStrategy(rawValue: value)
    }

    private static func tabStrategyFlag(_ arguments: [String]) -> FocusTabStrategy? {
        guard let value = stringFlag(arguments, "--strategy") else { return nil }
        return FocusTabStrategy(rawValue: value)
    }
}

struct V2Runner {
    private let processSource = ProcessSource()
    private let persistedSource = PersistedStateSource()
    private let liveWindowSource = LiveWindowSource()
    private let axWindowSource = AXWindowSource()
    private let windowMenuSource = WindowMenuSource()
    private let focusedTabsSource = FocusedTabsSource()
    private let windowMatcher = WindowMatcher()
    private let menuMatcher = MenuMatcher()
    private let focusedWindowMatcher = FocusedWindowMatcher()
    private let focusedTabsMatcher = FocusedTabsMatcher()
    private let windowFocuser = WindowFocuser()

    func run(_ command: V2Command) -> Int32 {
        switch command {
        case .help:
            printHelp()
            return 0
        case .list:
            return runList()
        case let .userFocusWindow(windowID, timeoutMS):
            return runActionFocusWindow(windowID: windowID, strategy: .menuOnly, timeoutMS: timeoutMS)
        case let .userFocusTab(windowID, tabID, tabTitle, timeoutMS):
            return runUserFocusTab(windowID: windowID, tabID: tabID, tabTitle: tabTitle, timeoutMS: timeoutMS)
        case .env:
            return runEnv()
        case .sourcePersisted:
            return runSourcePersisted()
        case let .sourcePersistedWatch(duration, thresholdMS):
            return runSourcePersistedWatch(duration: duration, thresholdMS: thresholdMS)
        case let .sourceSampleState(samples, intervalMS):
            return runSourceSampleState(samples: samples, intervalMS: intervalMS)
        case .sourceLiveWindows:
            return runSourceLiveWindows()
        case .sourceAXWindows:
            return runSourceAXWindows()
        case .sourceFocusedWindow:
            return runSourceFocusedWindow()
        case .sourceFocusDiagnostics:
            return runSourceFocusDiagnostics()
        case .sourceWindowMenu:
            return runSourceWindowMenu()
        case let .sourceFocusedTabs(strict):
            return runSourceFocusedTabs(strict: strict)
        case .sourceFocusedTabWebAreas:
            return runSourceFocusedTabWebAreas()
        case let .sourceFocusedAXTree(depth):
            return runSourceFocusedAXTree(depth: depth)
        case let .sourcePointDiagnostics(x, y):
            return runSourcePointDiagnostics(x: x, y: y)
        case .bridgeWindows:
            return runBridgeWindows()
        case .bridgeMenu:
            return runBridgeMenu()
        case let .bridgeFocusedWindow(windowID):
            return runBridgeFocusedWindow(windowID: windowID)
        case let .bridgeFocusedTabs(windowID):
            return runBridgeFocusedTabs(windowID: windowID)
        case let .bridgeTabObservation(windowID):
            return runBridgeTabObservation(windowID: windowID)
        case let .actionFocusWindow(windowID, strategy, timeoutMS):
            return runActionFocusWindow(windowID: windowID, strategy: strategy, timeoutMS: timeoutMS)
        case let .actionFocusTab(windowID, tabID, tabTitle, strategy, timeoutMS):
            return runActionFocusTab(windowID: windowID, tabID: tabID, tabTitle: tabTitle, strategy: strategy, timeoutMS: timeoutMS)
        }
    }

    private func printHelp() {
        print("""
        notion-tabs-v2 commands:
          list
          focus-window --window-id ID [--timeout-ms N]
          focus-tab --window-id ID [--tab-id ID|--tab-title TITLE] [--timeout-ms N]

        diagnostics:
          env
          source persisted
          source persisted-watch [--duration N] [--threshold-ms N]
          source sample-state [--samples N] [--interval-ms N]
          source live-windows
          source ax-windows
          source focused-window
          source focus-diagnostics
          source window-menu
          source focused-tabs [--strict|--raw]
          source focused-tab-webareas
          source focused-ax-tree [--depth N]
          source point-diagnostics --x X --y Y
          bridge windows
          bridge menu
          bridge focused-window --window-id ID
          bridge focused-tabs --window-id ID
          bridge tab-observation --window-id ID
          action focus-window --window-id ID [--strategy app-first|menu-only] [--timeout-ms N]
          action focus-tab --window-id ID [--tab-id ID|--tab-title TITLE] [--strategy press-only|scroll-then-press|coordinate-click] [--timeout-ms N]

        User commands use validated defaults:
          focus-window uses Window menu only.
          focus-tab uses coordinate click after bringing Notion frontmost.

        Phase 1 rule:
          source commands are read-only and must not activate windows or press tabs.
        Phase 2 rule:
          bridge commands read multiple sources and report matched, missing, or ambiguous.
        Phase 3 rule:
          action focus-window may focus a window, but must not press tabs.
        """)
    }

    private func runEnv() -> Int32 {
        let logger = RunLogger(commandName: "env")
        let started = Date()
        let process = processSource.find().record
        let trusted = AXIsProcessTrusted()
        logger.recordSource(name: "process", payload: process.jsonValue())
        logger.recordSource(name: "accessibility", payload: JSONValue.object(["trusted": .bool(trusted)]))

        logger.event(
            phase: .environment,
            step: "process",
            status: process.found ? .pass : .blocked,
            message: process.found ? "Notion process found" : "Notion process not found",
            evidence: process.jsonValue()
        )
        logger.event(
            phase: .environment,
            step: "accessibility",
            status: trusted ? .pass : .blocked,
            message: trusted ? "Accessibility permission trusted" : "Accessibility permission not trusted",
            evidence: .object(["trusted": .bool(trusted)])
        )

        let verdict: Verdict = process.found && trusted ? .pass : .blocked
        let summary = process.found && trusted ? "Environment ready." : "Environment blocked. Open Notion and grant Accessibility permission."
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A0",
            summary: summary,
            counts: ["elapsed_ms": Int(Date().timeIntervalSince(started) * 1000)]
        )
    }

    private func runSourcePersisted() -> Int32 {
        let logger = RunLogger(commandName: "source persisted")
        do {
            let snapshot = try persistedSource.read()
            logger.recordSource(name: "persisted", payload: snapshot.jsonValue())
            printPersisted(snapshot)

            let verdict: Verdict = snapshot.windows.contains(where: { !$0.tabs.isEmpty }) ? .pass : .fail
            logger.event(
                phase: .source,
                step: "read-persisted",
                status: verdict,
                message: "windows=\(snapshot.windows.count) tabs=\(snapshot.windows.reduce(0) { $0 + $1.tabs.count }) ageSeconds=\(format(snapshot.ageSeconds))",
                evidence: snapshot.jsonValue()
            )
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A1",
                summary: verdict == .pass ? "Persisted state parsed." : "Persisted state parsed but did not contain usable windows/tabs.",
                counts: [
                    "persisted_windows": snapshot.windows.count,
                    "persisted_tabs": snapshot.windows.reduce(0) { $0 + $1.tabs.count }
                ]
            )
        } catch {
            logger.event(phase: .source, step: "read-persisted", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A1", summary: "\(error)")
        }
    }

    private func runList() -> Int32 {
        let logger = RunLogger(commandName: "list")
        guard let app = requireNotion(logger: logger, assumption: "LIST") else {
            return logger.finish(verdict: .blocked, failedAssumption: "LIST", summary: "Notion process not found.")
        }

        do {
            let snapshot = try persistedSource.read()
            let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let axWindows = axWindowSource.read(pid: app.processIdentifier)
            let menuItems = windowMenuSource.read(pid: app.processIdentifier)
            logger.recordSource(name: "persisted", payload: snapshot.jsonValue())
            logger.recordSource(name: "focused_window", payload: focused?.jsonValue() ?? .null)
            logger.recordSource(name: "ax_windows", payload: axWindows.jsonValue())
            logger.recordSource(name: "window_menu", payload: menuItems.jsonValue())

            print("focusedAX='\(focused?.title ?? "<nil>")' frame=\(focused?.frame.map(rect) ?? "<nil>")")
            print("statePath=\(snapshot.path)")
            print("stateModifiedAt=\(snapshot.modifiedAt ?? "<nil>") ageSeconds=\(format(snapshot.ageSeconds))")
            print("hint=use window index/id and tab index/id, e.g. focus-tab --window-id 3 --tab-id 1")
            print("windows=\(snapshot.windows.count)")
            for window in snapshot.windows {
                let titleMatchedAX = axWindows.contains { normalize($0.title) == normalize(window.activeTitle) }
                let titleInMenu = menuItems.contains { $0.category == "document_candidate" && normalize($0.title) == normalize(window.activeTitle) }
                let focusedMark = normalize(focused?.title ?? "") == normalize(window.activeTitle) ? "*" : " "
                print("\(focusedMark) [Window \(window.index)] id=\(shortID(window.windowID)) active='\(window.activeTitle)' tabs=\(window.tabs.count) axTitle=\(titleMatchedAX) menuTitle=\(titleInMenu)")
                for tab in window.tabs {
                    let activeMark = normalize(tab.title) == normalize(focused?.title ?? "") ? ">" : (normalize(tab.title) == normalize(window.activeTitle) ? "*" : " ")
                    print("    \(activeMark) [\(tab.index)] id=\(shortID(tab.tabID)) \(tab.title)")
                }
            }

            logger.event(
                phase: .source,
                step: "list",
                status: .pass,
                message: "windows=\(snapshot.windows.count) focusedAX='\(focused?.title ?? "<nil>")'"
            )
            return logger.finish(
                verdict: .pass,
                failedAssumption: nil,
                summary: "windows=\(snapshot.windows.count) focusedAX='\(focused?.title ?? "<nil>")'",
                counts: ["windows": snapshot.windows.count]
            )
        } catch {
            logger.event(phase: .source, step: "list", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "LIST", summary: "\(error)")
        }
    }

    private func runSourcePersistedWatch(duration: Int, thresholdMS: Int) -> Int32 {
        let logger = RunLogger(commandName: "source persisted-watch")
        let end = Date().addingTimeInterval(TimeInterval(max(1, duration)))
        var lastSignature: String?
        var changes = 0

        logger.event(
            phase: .source,
            step: "watch-start",
            status: .info,
            message: "Watching persisted state for \(duration)s; thresholdMS=\(thresholdMS)"
        )

        while Date() < end {
            do {
                let snapshot = try persistedSource.read()
                let signature = persistedSignature(snapshot)
                if signature != lastSignature {
                    changes += 1
                    lastSignature = signature
                    logger.recordSource(name: "persisted-change-\(changes)", payload: snapshot.jsonValue())
                    logger.event(
                        phase: .source,
                        step: "persisted-change",
                        status: .info,
                        message: "change=\(changes) windows=\(snapshot.windows.count) tabs=\(snapshot.windows.reduce(0) { $0 + $1.tabs.count }) ageSeconds=\(format(snapshot.ageSeconds))",
                        evidence: snapshot.jsonValue()
                    )
                }
            } catch {
                logger.event(phase: .source, step: "watch-error", status: .blocked, message: "\(error)")
                return logger.finish(verdict: .blocked, failedAssumption: "A2", summary: "\(error)")
            }
            usleep(250_000)
        }

        let verdict: Verdict = changes > 0 ? .pass : .blocked
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A2",
            summary: changes > 0 ? "Persisted watch observed \(changes) snapshot(s)." : "No persisted snapshots observed.",
            counts: ["changes": changes]
        )
    }

    private func runSourceSampleState(samples: Int, intervalMS: Int) -> Int32 {
        let logger = RunLogger(commandName: "source sample-state")
        guard let app = requireNotion(logger: logger, assumption: "A2") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A2", summary: "Notion process not found.")
        }

        let sampleCount = max(1, samples)
        let interval = max(100, intervalMS)
        let start = Date()
        var records: [StateSampleRecord] = []
        var persistedSignatures: [String] = []
        var axSignatures: [String] = []

        logger.event(
            phase: .source,
            step: "sample-start",
            status: .info,
            message: "Sampling persisted + AX focused state samples=\(sampleCount) intervalMS=\(interval)"
        )

        for index in 1 ... sampleCount {
            let now = Date()
            let persisted = try? persistedSource.read()
            let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let strictTabs = focusedTabsSource.read(pid: app.processIdentifier, strict: true)
            let rawTabs = focusedTabsSource.read(pid: app.processIdentifier, strict: false)
            let record = StateSampleRecord(
                index: index,
                elapsedMS: Int(now.timeIntervalSince(start) * 1000),
                sampledAt: isoString(now),
                persistedModifiedAt: persisted?.modifiedAt,
                persistedAgeSeconds: persisted?.ageSeconds,
                persistedWindows: persisted?.windows.map {
                    PersistedWindowStateRecord(windowID: $0.windowID, activeTitle: $0.activeTitle, tabCount: $0.tabs.count)
                } ?? [],
                axFocusedWindow: focused,
                axFocusedTabsStrict: strictTabs,
                axFocusedTabsRaw: rawTabs
            )
            records.append(record)

            let persistedSignature = persisted.map(persistedSignature) ?? "<persisted-error>"
            let axSignature = "\(focused?.title ?? "<none>")|\(strictTabs.map(\.title).joined(separator: "|"))"
            persistedSignatures.append(persistedSignature)
            axSignatures.append(axSignature)

            let persistedActive = record.persistedWindows.map { shortID($0.windowID) + ":" + $0.activeTitle }.joined(separator: " | ")
            let axTitle = focused?.title ?? "<none>"
            print("[\(index)/\(sampleCount)] elapsed=\(record.elapsedMS)ms persistedAge=\(format(record.persistedAgeSeconds)) axFocused='\(axTitle)' strictTabs=\(strictTabs.count)")
            print("  persistedActive=\(persistedActive)")
            print("  axStrictTabs=\(strictTabs.map(\.title).joined(separator: " | "))")

            logger.event(
                phase: .source,
                step: "sample-\(index)",
                status: .info,
                message: "axFocused='\(axTitle)' persistedWindows=\(record.persistedWindows.count) strictTabs=\(strictTabs.count)",
                evidence: record.jsonValue()
            )

            if index < sampleCount {
                usleep(useconds_t(interval * 1000))
            }
        }

        logger.recordSource(name: "state_samples", payload: records.jsonValue())
        let persistedChanges = countTransitions(persistedSignatures)
        let axChanges = countTransitions(axSignatures)
        let summary = "samples=\(records.count) persistedTransitions=\(persistedChanges) axTransitions=\(axChanges)"
        logger.event(phase: .source, step: "sample-summary", status: .pass, message: summary)
        return logger.finish(
            verdict: .pass,
            failedAssumption: nil,
            summary: summary,
            counts: [
                "samples": records.count,
                "persisted_transitions": persistedChanges,
                "ax_transitions": axChanges
            ]
        )
    }

    private func runSourceLiveWindows() -> Int32 {
        let logger = RunLogger(commandName: "source live-windows")
        guard let app = requireNotion(logger: logger, assumption: "A3") else { return logger.finish(verdict: .blocked, failedAssumption: "A3", summary: "Notion process not found.") }

        let quartz = liveWindowSource.readQuartz(pid: app.processIdentifier)
        let scAll = liveWindowSource.readScreenCapture(bundleIdentifier: app.bundleIdentifier, onScreenOnly: false)
        let scOnscreen = liveWindowSource.readScreenCapture(bundleIdentifier: app.bundleIdentifier, onScreenOnly: true)
        let all = quartz + scAll + scOnscreen
        logger.recordSource(name: "quartz", payload: quartz.jsonValue())
        logger.recordSource(name: "screen_capture_all", payload: scAll.jsonValue())
        logger.recordSource(name: "screen_capture_onscreen", payload: scOnscreen.jsonValue())

        for record in all {
            print("[\(record.source) \(record.index)] id=\(record.windowID ?? "<nil>") title='\(record.title ?? "")' frame=\(rect(record.frame)) onscreen=\(record.isOnScreen.map(String.init) ?? "<nil>") active=\(record.isActive.map(String.init) ?? "<nil>")")
        }

        let verdict: Verdict = all.isEmpty ? .fail : .pass
        logger.event(phase: .source, step: "read-live-windows", status: verdict, message: "quartz=\(quartz.count) scAll=\(scAll.count) scOnscreen=\(scOnscreen.count)")
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A3",
            summary: verdict == .pass ? "Live window sources returned candidates." : "No live Notion windows found.",
            counts: ["quartz_windows": quartz.count, "screen_capture_all_windows": scAll.count, "screen_capture_onscreen_windows": scOnscreen.count]
        )
    }

    private func runSourceAXWindows() -> Int32 {
        let logger = RunLogger(commandName: "source ax-windows")
        guard let app = requireNotion(logger: logger, assumption: "A3") else { return logger.finish(verdict: .blocked, failedAssumption: "A3", summary: "Notion process not found.") }

        let windows = axWindowSource.read(pid: app.processIdentifier)
        logger.recordSource(name: "ax_windows", payload: windows.jsonValue())
        for window in windows {
            print("[AX \(window.index)] title='\(window.title)' role=\(window.role) frame=\(window.frame.map(rect) ?? "<nil>") focused=\(window.isFocused.map(String.init) ?? "<nil>") main=\(window.isMain.map(String.init) ?? "<nil>") minimized=\(window.isMinimized.map(String.init) ?? "<nil>")")
        }
        let verdict: Verdict = windows.isEmpty ? .fail : .pass
        logger.event(phase: .source, step: "read-ax-windows", status: verdict, message: "axWindows=\(windows.count)")
        return logger.finish(verdict: verdict, failedAssumption: verdict == .pass ? nil : "A3", summary: windows.isEmpty ? "AX returned no windows." : "AX windows read.", counts: ["ax_windows": windows.count])
    }

    private func runSourceFocusedWindow() -> Int32 {
        let logger = RunLogger(commandName: "source focused-window")
        guard let app = requireNotion(logger: logger, assumption: "A6") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Notion process not found.")
        }

        let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
        logger.recordSource(name: "focused_window", payload: focused?.jsonValue() ?? .null)

        if let focused {
            print("title='\(focused.title)'")
            print("role=\(focused.role)")
            print("frame=\(focused.frame.map(rect) ?? "<nil>")")
            print("focused=\(focused.isFocused.map(String.init) ?? "<nil>")")
            print("main=\(focused.isMain.map(String.init) ?? "<nil>")")
            print("minimized=\(focused.isMinimized.map(String.init) ?? "<nil>")")
            print("actions=[\(focused.actions.joined(separator: ","))]")
        } else {
            print("focused=<nil>")
        }

        let verdict: Verdict = focused == nil ? .fail : .pass
        logger.event(
            phase: .source,
            step: "read-focused-window",
            status: verdict,
            message: focused.map { "title='\($0.title)' frame=\($0.frame.map(rect) ?? "<nil>")" } ?? "No focused AX window",
            evidence: focused?.jsonValue() ?? .null
        )
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A6",
            summary: focused == nil ? "AX returned no focused window." : "AX focused window read.",
            counts: ["focused_window_present": focused == nil ? 0 : 1]
        )
    }

    private func runSourceFocusDiagnostics() -> Int32 {
        let logger = RunLogger(commandName: "source focus-diagnostics")
        guard let app = requireNotion(logger: logger, assumption: "A6") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Notion process not found.")
        }

        let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
        let axWindows = axWindowSource.read(pid: app.processIdentifier)
        let menuItems = windowMenuSource.read(pid: app.processIdentifier)
        let quartz = liveWindowSource.readQuartz(pid: app.processIdentifier)
        let screenCaptureAll = liveWindowSource.readScreenCapture(bundleIdentifier: app.bundleIdentifier, onScreenOnly: false)
        let persisted = try? persistedSource.read()

        logger.recordSource(name: "persisted", payload: persisted?.jsonValue() ?? .null)
        logger.recordSource(name: "focused_window", payload: focused?.jsonValue() ?? .null)
        logger.recordSource(name: "ax_windows", payload: axWindows.jsonValue())
        logger.recordSource(name: "window_menu", payload: menuItems.jsonValue())
        logger.recordSource(name: "quartz", payload: quartz.jsonValue())
        logger.recordSource(name: "screen_capture_all", payload: screenCaptureAll.jsonValue())

        print("persistedWindows=\(persisted?.windows.count ?? 0)")
        if let persisted {
            for window in persisted.windows {
                print("  [state \(window.index)] id='\(shortID(window.windowID))' active='\(window.activeTitle)' tabs=\(window.tabs.count) frame=\(rect(window.bounds))")
            }
        }

        if let focused {
            print("focusedWindow title='\(focused.title)' frame=\(focused.frame.map(rect) ?? "<nil>") focused=\(focused.isFocused.map(String.init) ?? "<nil>") main=\(focused.isMain.map(String.init) ?? "<nil>") minimized=\(focused.isMinimized.map(String.init) ?? "<nil>")")
        } else {
            print("focusedWindow=<nil>")
        }

        print("axWindows=\(axWindows.count)")
        for window in axWindows {
            print("  [ax \(window.index)] title='\(window.title)' frame=\(window.frame.map(rect) ?? "<nil>") focused=\(window.isFocused.map(String.init) ?? "<nil>") main=\(window.isMain.map(String.init) ?? "<nil>") minimized=\(window.isMinimized.map(String.init) ?? "<nil>") actions=[\(window.actions.joined(separator: ","))]")
        }

        let documentMenuItems = menuItems.filter { $0.category == "document_candidate" }
        print("windowMenuDocumentCandidates=\(documentMenuItems.count)")
        for item in documentMenuItems {
            print("  [menu \(item.index)] title='\(item.title)' selected=\(item.selected.map(String.init) ?? "<nil>") actions=[\(item.actions.joined(separator: ","))]")
        }

        print("quartzWindows=\(quartz.count)")
        for window in quartz {
            print("  [quartz \(window.index)] id=\(window.windowID ?? "<nil>") title='\(window.title ?? "")' frame=\(rect(window.frame)) onscreen=\(window.isOnScreen.map(String.init) ?? "<nil>")")
        }

        print("screenCaptureAllWindows=\(screenCaptureAll.count)")
        for window in screenCaptureAll {
            print("  [sc-all \(window.index)] id=\(window.windowID ?? "<nil>") title='\(window.title ?? "")' frame=\(rect(window.frame)) onscreen=\(window.isOnScreen.map(String.init) ?? "<nil>")")
        }

        let verdict: Verdict = focused != nil || !axWindows.isEmpty || !documentMenuItems.isEmpty || !(persisted?.windows.isEmpty ?? true) ? .pass : .fail
        logger.event(
            phase: .source,
            step: "read-focus-diagnostics",
            status: verdict,
            message: "focused=\(focused == nil ? 0 : 1) axWindows=\(axWindows.count) menuDocuments=\(documentMenuItems.count) persistedWindows=\(persisted?.windows.count ?? 0)",
            evidence: .object([
                "focusedWindow": focused?.jsonValue() ?? .null,
                "axWindows": axWindows.jsonValue(),
                "windowMenu": menuItems.jsonValue(),
                "persisted": persisted?.jsonValue() ?? .null
            ])
        )
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A6",
            summary: "focused=\(focused == nil ? 0 : 1) axWindows=\(axWindows.count) menuDocuments=\(documentMenuItems.count) persistedWindows=\(persisted?.windows.count ?? 0)",
            counts: [
                "focused_window_present": focused == nil ? 0 : 1,
                "ax_windows": axWindows.count,
                "window_menu_document_candidates": documentMenuItems.count,
                "persisted_windows": persisted?.windows.count ?? 0,
                "quartz_windows": quartz.count,
                "screen_capture_all_windows": screenCaptureAll.count
            ]
        )
    }

    private func runSourceWindowMenu() -> Int32 {
        let logger = RunLogger(commandName: "source window-menu")
        guard let app = requireNotion(logger: logger, assumption: "A5") else { return logger.finish(verdict: .blocked, failedAssumption: "A5", summary: "Notion process not found.") }

        let items = windowMenuSource.read(pid: app.processIdentifier)
        let documentCount = items.filter { $0.category == "document_candidate" }.count
        logger.recordSource(name: "window_menu", payload: items.jsonValue())
        for item in items {
            print("[Menu \(item.index)] category=\(item.category) title='\(item.title)' selected=\(item.selected.map(String.init) ?? "<nil>") actions=[\(item.actions.joined(separator: ","))]")
        }
        let verdict: Verdict = documentCount > 0 ? .pass : .fail
        logger.event(phase: .source, step: "read-window-menu", status: verdict, message: "items=\(items.count) documentCandidates=\(documentCount)")
        return logger.finish(verdict: verdict, failedAssumption: verdict == .pass ? nil : "A5", summary: documentCount > 0 ? "Window menu has document candidates." : "Window menu has no document candidates.", counts: ["menu_items": items.count, "menu_document_candidates": documentCount])
    }

    private func runSourceFocusedTabs(strict: Bool) -> Int32 {
        let logger = RunLogger(commandName: strict ? "source focused-tabs strict" : "source focused-tabs raw")
        guard let app = requireNotion(logger: logger, assumption: "A7") else { return logger.finish(verdict: .blocked, failedAssumption: "A7", summary: "Notion process not found.") }

        let tabs = focusedTabsSource.read(pid: app.processIdentifier, strict: strict)
        logger.recordSource(name: strict ? "focused_tabs_strict" : "focused_tabs_raw", payload: tabs.jsonValue())
        for tab in tabs {
            print("[Tab \(tab.index)] title='\(tab.title)' role=\(tab.role) selected=\(tab.selected.map(String.init) ?? "<nil>") frame=\(tab.frame.map(rect) ?? "<nil>") actions=[\(tab.actions.joined(separator: ","))]")
        }
        let verdict: Verdict = tabs.isEmpty ? .fail : .pass
        logger.event(phase: .source, step: "read-focused-tabs", status: verdict, message: "mode=\(strict ? "strict" : "raw") tabs=\(tabs.count)")
        return logger.finish(verdict: verdict, failedAssumption: verdict == .pass ? nil : "A7", summary: tabs.isEmpty ? "Focused window exposed no tab candidates." : "Focused tabs read.", counts: ["focused_tabs": tabs.count])
    }

    private func runSourceFocusedTabWebAreas() -> Int32 {
        let logger = RunLogger(commandName: "source focused-tab-webareas")
        guard let app = requireNotion(logger: logger, assumption: "A7") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A7", summary: "Notion process not found.")
        }

        let tabs = focusedTabsSource.readWebAreas(pid: app.processIdentifier)
        logger.recordSource(name: "focused_tab_webareas", payload: tabs.jsonValue())
        for tab in tabs {
            print("[WebArea \(tab.index)] title='\(tab.title)' selected=\(tab.selected.map(String.init) ?? "<nil>") frame=\(tab.frame.map(rect) ?? "<nil>") actions=[\(tab.actions.joined(separator: ","))]")
        }
        let verdict: Verdict = tabs.isEmpty ? .fail : .pass
        logger.event(phase: .source, step: "read-focused-tab-webareas", status: verdict, message: "webAreas=\(tabs.count)")
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A7",
            summary: tabs.isEmpty ? "Focused window exposed no titled AXWebArea candidates." : "Focused titled AXWebArea candidates read.",
            counts: ["focused_tab_webareas": tabs.count]
        )
    }

    private func runSourceFocusedAXTree(depth: Int) -> Int32 {
        let logger = RunLogger(commandName: "source focused-ax-tree")
        guard let app = requireNotion(logger: logger, assumption: "A7") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A7", summary: "Notion process not found.")
        }
        guard let focused = AXElementV2.application(pid: app.processIdentifier).focusedWindow() else {
            logger.event(phase: .source, step: "read-focused-ax-tree", status: .fail, message: "No focused AX window")
            return logger.finish(verdict: .fail, failedAssumption: "A7", summary: "No focused AX window")
        }

        let safeDepth = max(1, depth)
        let dump = AXTreeDumperV2(maxDepth: safeDepth, maxChildren: 80).dump(element: focused)
        let roles = summarizeRoles(root: focused, maxDepth: safeDepth)
        let buttonLike = collectButtonLike(root: focused, maxDepth: safeDepth)
        logger.writeText(dump, to: "ax-tree.txt")
        logger.recordSource(name: "focused_window", payload: (AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)?.jsonValue() ?? .null))
        logger.recordSource(name: "role_counts", payload: roles.jsonValue())
        logger.recordSource(name: "button_like", payload: buttonLike.jsonValue())

        print("focused title='\(focused.title())' role=\(focused.role()) frame=\(focused.frame().map { RectRecord($0) }.map(rect) ?? "<nil>")")
        print("roleCounts:")
        for item in roles.sorted(by: { $0.key < $1.key }) {
            print("  \(item.key)=\(item.value)")
        }
        print("buttonLike=\(buttonLike.count)")
        for item in buttonLike.prefix(80) {
            print("  depth=\(item.depth) role=\(item.role) title='\(item.title)' value='\(item.value ?? "")' frame=\(item.frame.map(rect) ?? "<nil>") actions=[\(item.actions.joined(separator: ","))]")
        }
        print("axTreeFile=\(logger.runDirectory.appendingPathComponent("ax-tree.txt").path)")

        logger.event(
            phase: .source,
            step: "read-focused-ax-tree",
            status: .pass,
            message: "roles=\(roles.count) buttonLike=\(buttonLike.count)",
            evidence: .object(["roles": roles.jsonValue(), "buttonLike": buttonLike.jsonValue()])
        )
        return logger.finish(
            verdict: .pass,
            failedAssumption: nil,
            summary: "Focused AX tree dumped.",
            counts: ["role_types": roles.count, "button_like": buttonLike.count]
        )
    }

    private func runSourcePointDiagnostics(x: Int, y: Int) -> Int32 {
        let logger = RunLogger(commandName: "source point-diagnostics")
        let point = CGPoint(x: x, y: y)
        let windows = readPointWindows(point: point)
        logger.recordSource(name: "point", payload: JSONValue.object(["x": .int(x), "y": .int(y)]))
        logger.recordSource(name: "windows_at_point", payload: windows.jsonValue())

        print("point=(x:\(x),y:\(y)) windowsAtPoint=\(windows.count)")
        for window in windows.prefix(30) {
            print("[\(window.index)] owner='\(window.ownerName)' pid=\(window.ownerPID) title='\(window.title ?? "")' layer=\(window.layer) alpha=\(format(window.alpha)) onscreen=\(window.isOnScreen.map(String.init) ?? "<nil>") frame=\(rect(window.frame))")
        }

        let top = windows.first
        let verdict: Verdict = top == nil ? .fail : .pass
        let summary = top.map { "top owner='\($0.ownerName)' title='\($0.title ?? "")' layer=\($0.layer)" } ?? "no window at point"
        logger.event(phase: .source, step: "read-point-diagnostics", status: verdict, message: summary, evidence: windows.jsonValue())
        return logger.finish(
            verdict: verdict,
            failedAssumption: verdict == .pass ? nil : "A9",
            summary: summary,
            counts: ["windows_at_point": windows.count]
        )
    }

    private func runBridgeWindows() -> Int32 {
        let logger = RunLogger(commandName: "bridge windows")
        guard let app = requireNotion(logger: logger, assumption: "A4") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A4", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            let quartz = liveWindowSource.readQuartz(pid: app.processIdentifier)
            let scAll = liveWindowSource.readScreenCapture(bundleIdentifier: app.bundleIdentifier, onScreenOnly: false)
            let live = quartz + scAll
            let matches = windowMatcher.match(persisted: persisted.windows, live: live)
            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "quartz", payload: quartz.jsonValue())
            logger.recordSource(name: "screen_capture_all", payload: scAll.jsonValue())
            logger.recordSource(name: "window_bridge", payload: matches.jsonValue())

            for match in matches {
                print("[Window \(match.persistedWindow.index)] decision=\(match.decision) active='\(match.persistedWindow.activeTitle)' reason=\(match.reason)")
                for candidate in match.candidates {
                    print("  - \(candidate.source)[\(candidate.index)] score=\(candidate.score) title='\(candidate.title ?? "")' frame=\(rect(candidate.frame)) reason=\(candidate.reason)")
                }
            }

            let verdict = bridgeVerdict(decisions: matches.map(\.decision))
            logger.event(
                phase: .bridge,
                step: "match-windows",
                status: verdict,
                message: bridgeSummary(decisions: matches.map(\.decision)),
                evidence: matches.jsonValue()
            )
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A4",
                summary: bridgeSummary(decisions: matches.map(\.decision)),
                counts: [
                    "persisted_windows": persisted.windows.count,
                    "quartz_windows": quartz.count,
                    "screen_capture_all_windows": scAll.count,
                    "matched": matches.filter { $0.decision == "matched" }.count,
                    "missing": matches.filter { $0.decision == "missing" }.count,
                    "ambiguous": matches.filter { $0.decision == "ambiguous" }.count
                ]
            )
        } catch {
            logger.event(phase: .bridge, step: "match-windows", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A4", summary: "\(error)")
        }
    }

    private func runBridgeMenu() -> Int32 {
        let logger = RunLogger(commandName: "bridge menu")
        guard let app = requireNotion(logger: logger, assumption: "A5") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A5", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            let menuItems = windowMenuSource.read(pid: app.processIdentifier)
            let matches = menuMatcher.match(persisted: persisted.windows, menuItems: menuItems)
            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "window_menu", payload: menuItems.jsonValue())
            logger.recordSource(name: "menu_bridge", payload: matches.jsonValue())

            for match in matches {
                print("[Window \(match.persistedWindow.index)] decision=\(match.decision) active='\(match.persistedWindow.activeTitle)' reason=\(match.reason)")
                for candidate in match.candidates {
                    print("  - menu[\(candidate.index)] score=\(candidate.score) category=\(candidate.category) title='\(candidate.title)' reason=\(candidate.reason)")
                }
            }

            let documentCount = menuItems.filter { $0.category == "document_candidate" }.count
            let verdict = bridgeVerdict(decisions: matches.map(\.decision))
            logger.event(
                phase: .bridge,
                step: "match-menu",
                status: verdict,
                message: bridgeSummary(decisions: matches.map(\.decision)),
                evidence: matches.jsonValue()
            )
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A5",
                summary: bridgeSummary(decisions: matches.map(\.decision)),
                counts: [
                    "persisted_windows": persisted.windows.count,
                    "menu_items": menuItems.count,
                    "menu_document_candidates": documentCount,
                    "matched": matches.filter { $0.decision == "matched" }.count,
                    "missing": matches.filter { $0.decision == "missing" }.count,
                    "ambiguous": matches.filter { $0.decision == "ambiguous" }.count
                ]
            )
        } catch {
            logger.event(phase: .bridge, step: "match-menu", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A5", summary: "\(error)")
        }
    }

    private func runBridgeFocusedWindow(windowID: String) -> Int32 {
        let logger = RunLogger(commandName: "bridge focused-window")
        guard let app = requireNotion(logger: logger, assumption: "A6") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            guard let target = findPersistedWindow(windowID: windowID, snapshot: persisted) else {
                logger.event(phase: .bridge, step: "resolve-target", status: .blocked, message: "Persisted window id not found: \(windowID)")
                return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Persisted window id not found: \(windowID)")
            }
            let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let bridge = focusedWindowMatcher.match(target: target, focused: focused)
            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "focused_window", payload: (focused?.jsonValue() ?? .null))
            logger.recordSource(name: "focused_window_bridge", payload: bridge.jsonValue())

            printFocusedWindowBridge(bridge)
            let verdict = verdictForDecision(bridge.decision)
            logger.event(phase: .bridge, step: "match-focused-window", status: verdict, message: bridge.reason, evidence: bridge.jsonValue())
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A6",
                summary: bridge.reason,
                counts: ["focused_window_present": focused == nil ? 0 : 1]
            )
        } catch {
            logger.event(phase: .bridge, step: "match-focused-window", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "\(error)")
        }
    }

    private func runBridgeFocusedTabs(windowID: String) -> Int32 {
        let logger = RunLogger(commandName: "bridge focused-tabs")
        guard let app = requireNotion(logger: logger, assumption: "A8") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            guard let target = findPersistedWindow(windowID: windowID, snapshot: persisted) else {
                logger.event(phase: .bridge, step: "resolve-target", status: .blocked, message: "Persisted window id not found: \(windowID)")
                return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "Persisted window id not found: \(windowID)")
            }

            let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let focusedWindowBridge = focusedWindowMatcher.match(target: target, focused: focused)
            let strictTabs = focusedTabsSource.read(pid: app.processIdentifier, strict: true)
            let bridge = focusedTabsMatcher.match(
                targetWindow: target,
                focusedWindowBridge: focusedWindowBridge,
                axTabs: strictTabs
            )

            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "focused_window", payload: (focused?.jsonValue() ?? .null))
            logger.recordSource(name: "focused_tabs_strict", payload: strictTabs.jsonValue())
            logger.recordSource(name: "focused_tabs_bridge", payload: bridge.jsonValue())

            printFocusedTabsBridge(bridge)
            let verdict = verdictForDecision(bridge.decision)
            logger.event(phase: .bridge, step: "match-focused-tabs", status: verdict, message: bridge.reason, evidence: bridge.jsonValue())
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A8",
                summary: bridge.reason,
                counts: [
                    "persisted_tabs": target.tabs.count,
                    "ax_tabs": strictTabs.count,
                    "matched": bridge.tabMatches.filter { $0.decision == "matched" }.count,
                    "missing": bridge.tabMatches.filter { $0.decision == "missing" }.count,
                    "ambiguous": bridge.tabMatches.filter { $0.decision == "ambiguous" }.count
                ]
            )
        } catch {
            logger.event(phase: .bridge, step: "match-focused-tabs", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "\(error)")
        }
    }

    private func runBridgeTabObservation(windowID: String) -> Int32 {
        let logger = RunLogger(commandName: "bridge tab-observation")
        guard let app = requireNotion(logger: logger, assumption: "A8") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            guard let target = findPersistedWindow(windowID: windowID, snapshot: persisted) else {
                logger.event(phase: .bridge, step: "resolve-target", status: .blocked, message: "Persisted window id not found: \(windowID)")
                return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "Persisted window id not found: \(windowID)")
            }

            let focused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let focusedWindowBridge = focusedWindowMatcher.match(target: target, focused: focused)
            guard let focusedWindow = AXElementV2.application(pid: app.processIdentifier).focusedWindow() else {
                logger.event(phase: .bridge, step: "observe-tabs", status: .fail, message: "No focused AX window")
                return logger.finish(verdict: .fail, failedAssumption: "A8", summary: "No focused AX window")
            }

            let candidates = collectTabObservationCandidates(root: focusedWindow, maxDepth: 18)
            let matches = target.tabs.map { matchObservedTab($0, candidates: candidates) }
            let bridge = makeTabObservationBridge(
                target: target,
                focusedWindowBridge: focusedWindowBridge,
                candidates: candidates,
                matches: matches
            )

            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "focused_window", payload: focused?.jsonValue() ?? .null)
            logger.recordSource(name: "tab_observation_candidates", payload: candidates.jsonValue())
            logger.recordSource(name: "tab_observation_bridge", payload: bridge.jsonValue())

            printTabObservationBridge(bridge)
            let verdict = verdictForDecision(bridge.decision)
            logger.event(phase: .bridge, step: "observe-tabs", status: verdict, message: bridge.reason, evidence: bridge.jsonValue())
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A8",
                summary: bridge.reason,
                counts: [
                    "persisted_tabs": target.tabs.count,
                    "ax_candidates": candidates.count,
                    "matched": matches.filter { $0.decision == "matched" }.count,
                    "missing": matches.filter { $0.decision == "missing" }.count,
                    "ambiguous": matches.filter { $0.decision == "ambiguous" }.count,
                    "clickable_candidates": candidates.filter(\.clickable).count,
                    "near_top_candidates": candidates.filter(\.nearTop).count
                ]
            )
        } catch {
            logger.event(phase: .bridge, step: "observe-tabs", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A8", summary: "\(error)")
        }
    }

    private func runActionFocusWindow(windowID: String, strategy: FocusStrategy, timeoutMS: Int) -> Int32 {
        let logger = RunLogger(commandName: "action focus-window")
        guard let app = requireNotion(logger: logger, assumption: "A6") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Notion process not found.")
        }

        do {
            let persisted = try persistedSource.read()
            guard let target = findPersistedWindow(windowID: windowID, snapshot: persisted) else {
                logger.event(phase: .action, step: "resolve-target", status: .blocked, message: "Persisted window id not found: \(windowID)")
                return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "Persisted window id not found: \(windowID)")
            }

            let menuItems = windowMenuSource.read(pid: app.processIdentifier)
            let preDiagnostics = collectFocusDiagnostics(app: app, persisted: persisted)
            let action = windowFocuser.focus(
                app: app,
                target: target,
                menuItems: menuItems,
                strategy: strategy,
                timeoutMS: max(50, timeoutMS)
            )
            let postDiagnostics = collectFocusDiagnostics(app: app, persisted: persisted)
            let validation = validateFocusAction(target: target, postDiagnostics: postDiagnostics, action: action)
            logger.recordSource(name: "persisted", payload: persisted.jsonValue())
            logger.recordSource(name: "window_menu", payload: menuItems.jsonValue())
            logger.recordSource(name: "pre_focus_diagnostics", payload: preDiagnostics.jsonValue())
            logger.recordSource(name: "focus_action", payload: action.jsonValue())
            logger.recordSource(name: "post_focus_diagnostics", payload: postDiagnostics.jsonValue())
            logger.recordSource(name: "focus_validation", payload: validation.jsonValue())

            printFocusAction(action)
            printFocusValidation(validation)
            let verdict = validation.verdict
            logger.event(phase: .action, step: "focus-window", status: verdict, message: validation.summary, evidence: validation.jsonValue())
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A6",
                summary: validation.summary,
                counts: [
                    "elapsed_ms": action.elapsedMS,
                    "target_present_in_menu": validation.targetPresentInMenu ? 1 : 0,
                    "target_present_in_ax_windows": validation.targetPresentInAXWindows ? 1 : 0,
                    "target_non_minimized_in_ax_windows": validation.targetNonMinimizedInAXWindows ? 1 : 0,
                    "focused_window_matches_target": validation.focusedWindowMatchesTarget ? 1 : 0
                ]
            )
        } catch {
            logger.event(phase: .action, step: "focus-window", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A6", summary: "\(error)")
        }
    }

    private func runActionFocusTab(windowID: String, tabID: String?, tabTitle: String?, strategy: FocusTabStrategy, timeoutMS: Int) -> Int32 {
        let logger = RunLogger(commandName: "action focus-tab")
        guard let app = requireNotion(logger: logger, assumption: "A9") else {
            return logger.finish(verdict: .blocked, failedAssumption: "A9", summary: "Notion process not found.")
        }

        do {
            let prePersisted = try persistedSource.read()
            guard let targetWindow = findPersistedWindow(windowID: windowID, snapshot: prePersisted) else {
                logger.event(phase: .action, step: "resolve-window", status: .blocked, message: "Persisted window id not found: \(windowID)")
                return logger.finish(verdict: .blocked, failedAssumption: "A9", summary: "Persisted window id not found: \(windowID)")
            }
            guard let targetTab = findPersistedTab(tabID: tabID, tabTitle: tabTitle, window: targetWindow) else {
                logger.event(phase: .action, step: "resolve-tab", status: .blocked, message: "Persisted tab not found")
                return logger.finish(verdict: .blocked, failedAssumption: "A9", summary: "Persisted tab not found. Provide --tab-id or exact --tab-title.")
            }

            let preFocused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let preFocusedBridge = focusedWindowMatcher.match(target: targetWindow, focused: preFocused)
            guard let focusedWindow = AXElementV2.application(pid: app.processIdentifier).focusedWindow() else {
                logger.event(phase: .action, step: "focused-window", status: .fail, message: "No focused AX window")
                return logger.finish(verdict: .fail, failedAssumption: "A9", summary: "No focused AX window")
            }

            let started = Date()
            let preCandidates = collectTabObservationCandidates(root: focusedWindow, maxDepth: 18)
            let preMatches = targetWindow.tabs.map { matchObservedTab($0, candidates: preCandidates) }
            let preBridge = makeTabObservationBridge(
                target: targetWindow,
                focusedWindowBridge: preFocusedBridge,
                candidates: preCandidates,
                matches: preMatches
            )
            let observedTargetWindow = preBridge.tabMatches.allSatisfy { $0.decision == "matched" }
            guard preFocusedBridge.decision == "matched" || preFocusedBridge.titleMatches || observedTargetWindow else {
                logger.recordSource(name: "pre_persisted", payload: prePersisted.jsonValue())
                logger.recordSource(name: "pre_tab_observation", payload: preBridge.jsonValue())
                logger.event(phase: .action, step: "precondition-focused-window", status: .blocked, message: preFocusedBridge.reason)
                return logger.finish(verdict: .blocked, failedAssumption: "A9", summary: "Target window is not focused or observable: \(preFocusedBridge.reason)")
            }

            guard let targetElement = findPreferredTabElement(root: focusedWindow, title: targetTab.title) else {
                let record = FocusTabActionRecord(
                    requestedWindowID: targetWindow.windowID,
                    requestedTabID: targetTab.tabID,
                    requestedTabTitle: targetTab.title,
                    targetWindowTitle: targetWindow.activeTitle,
                    strategy: strategy.rawValue,
                    preActiveTitle: targetWindow.activeTitle,
                    postActiveTitle: nil,
                    preFocusedWindow: preFocused,
                    postFocusedWindow: nil,
                    candidate: nil,
                    action: nil,
                    pressed: false,
                    stateChangedToTarget: false,
                    focusedTitleMatchesTarget: false,
                    decision: "missing",
                    reason: "preferred top clickable AXButton not found",
                    elapsedMS: Int(Date().timeIntervalSince(started) * 1000)
                )
                logger.recordSource(name: "pre_persisted", payload: prePersisted.jsonValue())
                logger.recordSource(name: "pre_tab_observation", payload: preBridge.jsonValue())
                logger.recordSource(name: "focus_tab_action", payload: record.jsonValue())
                printFocusTabAction(record)
                logger.event(phase: .action, step: "focus-tab", status: .fail, message: record.reason, evidence: record.jsonValue())
                return logger.finish(verdict: .fail, failedAssumption: "A9", summary: record.reason)
            }

            let candidate = makeTabObservationCandidate(index: 1, depth: 0, element: targetElement, windowFrame: focusedWindow.frame())
            if strategy == .coordinateClick {
                _ = app.activate(options: [.activateIgnoringOtherApps])
                _ = focusedWindow.perform("AXRaise" as CFString)
                usleep(500_000)
            }
            let action = performTabAction(targetElement, strategy: strategy)
            let pressed = action.pressed
            let postPersisted = waitForTabState(windowID: targetWindow.windowID, targetTitle: targetTab.title, timeoutMS: max(50, timeoutMS))
            let postFocused = AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier)
            let postActiveTitle = postPersisted.flatMap { findPersistedWindow(windowID: targetWindow.windowID, snapshot: $0)?.activeTitle }
            let stateChangedToTarget = normalize(postActiveTitle ?? "") == normalize(targetTab.title)
            let focusedTitleMatchesTarget = normalize(postFocused?.title ?? "") == normalize(targetTab.title)

            let decision: String
            let reason: String
            if !pressed {
                decision = "fail"
                reason = "AXPress failed on preferred tab button"
            } else if stateChangedToTarget || focusedTitleMatchesTarget {
                decision = "matched"
                reason = stateChangedToTarget ? "post state active title matched target" : "post AXFocusedWindow title matched target"
            } else {
                decision = "missing"
                reason = "pressed tab button but post-state did not confirm target"
            }

            let record = FocusTabActionRecord(
                requestedWindowID: targetWindow.windowID,
                requestedTabID: targetTab.tabID,
                requestedTabTitle: targetTab.title,
                targetWindowTitle: targetWindow.activeTitle,
                strategy: strategy.rawValue,
                preActiveTitle: targetWindow.activeTitle,
                postActiveTitle: postActiveTitle,
                preFocusedWindow: preFocused,
                postFocusedWindow: postFocused,
                candidate: candidate,
                action: action.action,
                pressed: pressed,
                stateChangedToTarget: stateChangedToTarget,
                focusedTitleMatchesTarget: focusedTitleMatchesTarget,
                decision: decision,
                reason: reason,
                elapsedMS: Int(Date().timeIntervalSince(started) * 1000)
            )

            logger.recordSource(name: "pre_persisted", payload: prePersisted.jsonValue())
            logger.recordSource(name: "pre_tab_observation", payload: preBridge.jsonValue())
            logger.recordSource(name: "post_persisted", payload: postPersisted?.jsonValue() ?? .null)
            logger.recordSource(name: "focus_tab_action", payload: record.jsonValue())

            printFocusTabAction(record)
            let verdict = verdictForDecision(record.decision)
            logger.event(phase: .action, step: "focus-tab", status: verdict, message: record.reason, evidence: record.jsonValue())
            return logger.finish(
                verdict: verdict,
                failedAssumption: verdict == .pass ? nil : "A9",
                summary: record.reason,
                counts: [
                    "pressed": pressed ? 1 : 0,
                    "state_changed_to_target": stateChangedToTarget ? 1 : 0,
                    "focused_title_matches_target": focusedTitleMatchesTarget ? 1 : 0,
                    "elapsed_ms": record.elapsedMS
                ]
            )
        } catch {
            logger.event(phase: .action, step: "focus-tab", status: .blocked, message: "\(error)")
            return logger.finish(verdict: .blocked, failedAssumption: "A9", summary: "\(error)")
        }
    }

    private func runUserFocusTab(windowID: String, tabID: String?, tabTitle: String?, timeoutMS: Int) -> Int32 {
        let windowExit = runActionFocusWindow(windowID: windowID, strategy: .menuOnly, timeoutMS: max(1000, timeoutMS))
        if windowExit != 0 && windowExit != Verdict.softPass.exitCode {
            return windowExit
        }
        return runActionFocusTab(windowID: windowID, tabID: tabID, tabTitle: tabTitle, strategy: .coordinateClick, timeoutMS: timeoutMS)
    }

    private func requireNotion(logger: RunLogger, assumption: String) -> NSRunningApplication? {
        let result = processSource.find()
        logger.recordSource(name: "process", payload: result.record.jsonValue())
        guard let app = result.app else {
            logger.event(phase: .environment, step: "process", status: .blocked, message: "Notion process not found", evidence: result.record.jsonValue())
            return nil
        }
        logger.event(phase: .environment, step: "process", status: .pass, message: "Notion process found pid=\(app.processIdentifier)", evidence: result.record.jsonValue())
        return app
    }

    private struct FocusDiagnosticsSnapshot: Codable {
        let persistedWindows: [PersistedWindowRecord]
        let focusedWindow: AXWindowRecord?
        let axWindows: [AXWindowRecord]
        let windowMenuItems: [MenuItemRecord]
        let quartzWindows: [LiveWindowRecord]
        let screenCaptureAllWindows: [LiveWindowRecord]
    }

    private struct FocusActionValidationRecord: Codable {
        let requestedWindowID: String
        let targetTitle: String
        let actionDecision: String
        let targetPresentInMenu: Bool
        let targetPresentInAXWindows: Bool
        let targetNonMinimizedInAXWindows: Bool
        let focusedWindowMatchesTarget: Bool
        let focusedWindowDecision: String
        let focusedWindowReason: String
        let verdictRawValue: String
        let summary: String

        var verdict: Verdict {
            switch verdictRawValue {
            case "pass": return .pass
            case "soft_pass": return .softPass
            case "ambiguous": return .ambiguous
            case "fail": return .fail
            case "blocked": return .blocked
            default: return .blocked
            }
        }
    }

    private struct PointWindowRecord: Codable {
        let index: Int
        let windowID: String?
        let ownerPID: Int
        let ownerName: String
        let title: String?
        let frame: RectRecord
        let layer: Int
        let alpha: Double
        let isOnScreen: Bool?
    }

    private func readPointWindows(point: CGPoint) -> [PointWindowRecord] {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var records: [PointWindowRecord] = []
        for row in rows {
            let boundsDict = row[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let frame = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )
            guard frame.contains(point) else { continue }
            let alpha = row[kCGWindowAlpha as String] as? Double ?? 0
            guard alpha > 0 else { continue }
            let onscreenRaw = row[kCGWindowIsOnscreen as String] as? Int
            let title = (row[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(PointWindowRecord(
                index: records.count + 1,
                windowID: row[kCGWindowNumber as String].map { "\($0)" },
                ownerPID: row[kCGWindowOwnerPID as String] as? Int ?? -1,
                ownerName: row[kCGWindowOwnerName as String] as? String ?? "",
                title: title?.isEmpty == true ? nil : title,
                frame: RectRecord(frame),
                layer: row[kCGWindowLayer as String] as? Int ?? -1,
                alpha: alpha,
                isOnScreen: onscreenRaw.map { $0 != 0 }
            ))
        }
        return records
    }

    private func collectFocusDiagnostics(app: NSRunningApplication, persisted: PersistedSnapshotRecord) -> FocusDiagnosticsSnapshot {
        FocusDiagnosticsSnapshot(
            persistedWindows: persisted.windows,
            focusedWindow: AXWindowInspector.focusedWindowRecord(pid: app.processIdentifier),
            axWindows: axWindowSource.read(pid: app.processIdentifier),
            windowMenuItems: windowMenuSource.read(pid: app.processIdentifier),
            quartzWindows: liveWindowSource.readQuartz(pid: app.processIdentifier),
            screenCaptureAllWindows: liveWindowSource.readScreenCapture(bundleIdentifier: app.bundleIdentifier, onScreenOnly: false)
        )
    }

    private func validateFocusAction(
        target: PersistedWindowRecord,
        postDiagnostics: FocusDiagnosticsSnapshot,
        action: FocusWindowActionRecord
    ) -> FocusActionValidationRecord {
        let normalizedTitle = normalize(target.activeTitle)
        let targetPresentInMenu = postDiagnostics.windowMenuItems.contains {
            $0.category == "document_candidate" && normalize($0.title) == normalizedTitle
        }
        let matchingAXWindows = postDiagnostics.axWindows.filter { normalize($0.title) == normalizedTitle }
        let targetPresentInAXWindows = !matchingAXWindows.isEmpty
        let targetNonMinimizedInAXWindows = matchingAXWindows.contains { $0.isMinimized != true }
        let focusedBridge = focusedWindowMatcher.match(target: target, focused: postDiagnostics.focusedWindow)
        let focusedWindowMatchesTarget = focusedBridge.decision == "matched"

        let verdict: Verdict
        let summary: String
        if !targetPresentInMenu {
            verdict = .fail
            summary = "target missing from Window menu after action"
        } else if !targetPresentInAXWindows {
            verdict = .fail
            summary = "target missing from AXWindows after action"
        } else if !targetNonMinimizedInAXWindows {
            verdict = .fail
            summary = "target still minimized in AXWindows after action"
        } else if !focusedWindowMatchesTarget {
            if focusedBridge.titleMatches {
                verdict = .softPass
                summary = "target restored and focused title matched, but frame changed after restore: \(focusedBridge.reason)"
            } else {
                verdict = verdictForDecision(focusedBridge.decision)
                summary = "target restored but focused verification failed: \(focusedBridge.reason)"
            }
        } else if action.decision != "matched" {
            if action.decision == "ambiguous", focusedBridge.titleMatches {
                verdict = .softPass
                summary = "focus action was frame-ambiguous, but target restored and focused title matched: \(action.reason)"
            } else {
                verdict = verdictForDecision(action.decision)
                summary = "focus action did not report matched: \(action.reason)"
            }
        } else {
            verdict = .pass
            summary = "target present, non-minimized, and AXFocusedWindow matched"
        }

        return FocusActionValidationRecord(
            requestedWindowID: target.windowID,
            targetTitle: target.activeTitle,
            actionDecision: action.decision,
            targetPresentInMenu: targetPresentInMenu,
            targetPresentInAXWindows: targetPresentInAXWindows,
            targetNonMinimizedInAXWindows: targetNonMinimizedInAXWindows,
            focusedWindowMatchesTarget: focusedWindowMatchesTarget,
            focusedWindowDecision: focusedBridge.decision,
            focusedWindowReason: focusedBridge.reason,
            verdictRawValue: verdict.rawValue,
            summary: summary
        )
    }

    private func collectTabObservationCandidates(root: AXElementV2, maxDepth: Int) -> [TabObservationCandidate] {
        let windowFrame = root.frame()
        var candidates: [TabObservationCandidate] = []
        var seen: Set<String> = []
        walkAX(root: root, maxDepth: maxDepth) { element, depth in
            guard depth > 0 else { return }
            let title = element.title().trimmingCharacters(in: .whitespacesAndNewlines)
            let value = element.valueString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label: String
            let labelSource: String
            if !title.isEmpty {
                label = title
                labelSource = "title"
            } else if !value.isEmpty {
                label = value
                labelSource = "value"
            } else {
                return
            }

            let candidate = makeTabObservationCandidate(
                index: candidates.count + 1,
                depth: depth,
                element: element,
                windowFrame: windowFrame,
                labelOverride: label,
                labelSourceOverride: labelSource
            )
            let frame = candidate.frame
            let key = "\(element.role())|\(label)|\(Int(frame?.x ?? -1))|\(Int(frame?.y ?? -1))|\(Int(frame?.width ?? -1))|\(Int(frame?.height ?? -1))"
            guard seen.insert(key).inserted else { return }
            candidates.append(candidate)
        }
        return candidates
    }

    private func makeTabObservationCandidate(
        index: Int,
        depth: Int,
        element: AXElementV2,
        windowFrame: CGRect?,
        labelOverride: String? = nil,
        labelSourceOverride: String? = nil
    ) -> TabObservationCandidate {
        let title = element.title().trimmingCharacters(in: .whitespacesAndNewlines)
        let value = element.valueString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = labelOverride ?? (!title.isEmpty ? title : value)
        let labelSource = labelSourceOverride ?? (!title.isEmpty ? "title" : "value")
        let frame = element.frame()
        let actions = element.actions()
        return TabObservationCandidate(
            index: index,
            depth: depth,
            role: element.role(),
            label: label,
            labelSource: labelSource,
            frame: frame.map(RectRecord.init),
            selected: element.isSelected(),
            actions: actions,
            nearTop: isNearTop(frame: frame, windowFrame: windowFrame),
            clickable: actions.contains(kAXPressAction as String) || actions.contains(kAXPickAction as String)
        )
    }

    private func isNearTop(frame: CGRect?, windowFrame: CGRect?) -> Bool {
        guard let frame, let windowFrame else { return false }
        return frame.minY - windowFrame.minY <= 44
    }

    private func matchObservedTab(_ tab: PersistedTabRecord, candidates: [TabObservationCandidate]) -> TabObservationMatchItem {
        let exact = candidates.filter { normalize($0.label) == normalize(tab.title) }
        let preferred = exact.filter { $0.role == "AXButton" && $0.nearTop && $0.clickable }
        let decision: String
        let reason: String
        if preferred.count == 1 {
            decision = "matched"
            reason = "exact title; one preferred top clickable AXButton candidate"
        } else if preferred.count > 1 {
            decision = "ambiguous"
            reason = "multiple preferred top clickable AXButton candidates have exact title"
        } else if exact.count == 1 {
            decision = "matched"
            reason = exact[0].clickable ? "exact title; one clickable non-preferred candidate" : "exact title; candidate is observable but not clickable"
        } else if exact.count > 1 {
            decision = "ambiguous"
            reason = "multiple AX candidates have exact title and no unique preferred candidate"
        } else {
            decision = "missing"
            reason = "no AX candidate with exact title"
        }
        return TabObservationMatchItem(persistedTab: tab, candidates: exact, decision: decision, reason: reason)
    }

    private func makeTabObservationBridge(
        target: PersistedWindowRecord,
        focusedWindowBridge: FocusedWindowBridgeRecord,
        candidates: [TabObservationCandidate],
        matches: [TabObservationMatchItem]
    ) -> TabObservationBridgeRecord {
        let decisions = matches.map(\.decision)
        let allTabsObserved = !matches.isEmpty && matches.allSatisfy { $0.decision == "matched" }
        let decision: String
        let reason: String
        if focusedWindowBridge.decision != "matched", !focusedWindowBridge.titleMatches, !allTabsObserved {
            decision = "missing"
            reason = "target window is not focused: \(focusedWindowBridge.reason)"
        } else if decisions.contains("ambiguous") {
            decision = "ambiguous"
            reason = "one or more persisted tabs matched multiple AX candidates"
        } else if decisions.contains("missing") {
            decision = "missing"
            reason = "one or more persisted tabs are missing from focused AX tree"
        } else if focusedWindowBridge.decision != "matched", !focusedWindowBridge.titleMatches {
            decision = "matched"
            reason = "all persisted tabs were observed; focused title likely differs because persisted activeTitle is stale"
        } else {
            decision = "matched"
            reason = "all persisted tabs were observed by exact title in focused AX tree"
        }

        return TabObservationBridgeRecord(
            requestedWindowID: target.windowID,
            targetWindowTitle: target.activeTitle,
            focusedWindowBridge: focusedWindowBridge,
            axCandidates: candidates,
            tabMatches: matches,
            decision: decision,
            reason: reason
        )
    }

    private func findPreferredTabElement(root: AXElementV2, title: String) -> AXElementV2? {
        let windowFrame = root.frame()
        var preferred: [AXElementV2] = []
        walkAX(root: root, maxDepth: 18) { element, depth in
            guard depth > 0 else { return }
            guard element.role() == "AXButton" else { return }
            guard normalize(element.title()) == normalize(title) else { return }
            guard isNearTop(frame: element.frame(), windowFrame: windowFrame) else { return }
            guard element.actions().contains(kAXPressAction as String) else { return }
            preferred.append(element)
        }
        return preferred.count == 1 ? preferred[0] : nil
    }

    private func performTabAction(_ element: AXElementV2, strategy: FocusTabStrategy) -> (action: String, pressed: Bool) {
        switch strategy {
        case .pressOnly:
            return (kAXPressAction as String, element.perform(kAXPressAction as CFString))
        case .scrollThenPress:
            let scrollAction = "AXScrollToVisible"
            let scrolled = element.perform(scrollAction as CFString)
            let pressed = element.perform(kAXPressAction as CFString)
            return ("\(scrollAction)+\((kAXPressAction as String));scroll=\(scrolled)", pressed)
        case .coordinateClick:
            guard let frame = element.frame() else {
                return ("coordinate-click;frame=nil", false)
            }
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let moved = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            moved?.post(tap: .cghidEventTap)
            usleep(20_000)
            down?.post(tap: .cghidEventTap)
            usleep(20_000)
            up?.post(tap: .cghidEventTap)
            return ("coordinate-click@\(Int(point.x)),\(Int(point.y))", down != nil && up != nil)
        }
    }

    private func printPersisted(_ snapshot: PersistedSnapshotRecord) {
        print("path=\(snapshot.path)")
        print("modifiedAt=\(snapshot.modifiedAt ?? "<nil>") ageSeconds=\(format(snapshot.ageSeconds)) byteSize=\(snapshot.byteSize ?? 0)")
        print("windowCount=\(snapshot.windows.count)")
        for window in snapshot.windows {
            print("[Window \(window.index)] id='\(window.windowID)' active='\(window.activeTitle)' frame=\(rect(window.bounds)) tabCount=\(window.tabs.count)")
            for tab in window.tabs {
                let marker = tab.title == window.activeTitle ? "*" : " "
                print("  \(marker) [\(tab.index)] id='\(tab.tabID)' \(tab.title)")
            }
        }
    }

    private func persistedSignature(_ snapshot: PersistedSnapshotRecord) -> String {
        snapshot.windows.map { window in
            "\(window.windowID)|\(window.activeTitle)|\(rect(window.bounds))|\(window.tabs.map { "\($0.tabID):\($0.title)" }.joined(separator: ","))"
        }.joined(separator: "||")
    }

    private func rect(_ rect: RectRecord) -> String {
        String(format: "(x:%.0f,y:%.0f,w:%.0f,h:%.0f)", rect.x, rect.y, rect.width, rect.height)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "<nil>" }
        return String(format: "%.2f", value)
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func countTransitions(_ values: [String]) -> Int {
        guard !values.isEmpty else { return 0 }
        var count = 0
        for idx in values.indices.dropFirst() where values[idx] != values[idx - 1] {
            count += 1
        }
        return count
    }

    private func bridgeVerdict(decisions: [String]) -> Verdict {
        if decisions.isEmpty { return .blocked }
        if decisions.contains("ambiguous") { return .ambiguous }
        if decisions.contains("missing") { return .fail }
        return .pass
    }

    private func bridgeSummary(decisions: [String]) -> String {
        let matched = decisions.filter { $0 == "matched" }.count
        let missing = decisions.filter { $0 == "missing" }.count
        let ambiguous = decisions.filter { $0 == "ambiguous" }.count
        return "matched=\(matched) missing=\(missing) ambiguous=\(ambiguous)"
    }

    private func findPersistedWindow(windowID: String, snapshot: PersistedSnapshotRecord) -> PersistedWindowRecord? {
        if let index = Int(windowID), let byIndex = snapshot.windows.first(where: { $0.index == index }) {
            return byIndex
        }
        if let exact = snapshot.windows.first(where: { $0.windowID == windowID }) {
            return exact
        }
        return snapshot.windows.first { $0.windowID.hasPrefix(windowID) }
    }

    private func findPersistedTab(tabID: String?, tabTitle: String?, window: PersistedWindowRecord) -> PersistedTabRecord? {
        if let tabID {
            if let index = Int(tabID), let byIndex = window.tabs.first(where: { $0.index == index }) {
                return byIndex
            }
            if let exact = window.tabs.first(where: { $0.tabID == tabID }) {
                return exact
            }
            if let prefixed = window.tabs.first(where: { $0.tabID.hasPrefix(tabID) }) {
                return prefixed
            }
        }
        if let tabTitle {
            let matches = window.tabs.filter { normalize($0.title) == normalize(tabTitle) }
            return matches.count == 1 ? matches[0] : nil
        }
        return nil
    }

    private func waitForTabState(windowID: String, targetTitle: String, timeoutMS: Int) -> PersistedSnapshotRecord? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        var latest: PersistedSnapshotRecord?
        while true {
            if let snapshot = try? persistedSource.read() {
                latest = snapshot
                if let window = findPersistedWindow(windowID: windowID, snapshot: snapshot), normalize(window.activeTitle) == normalize(targetTitle) {
                    return snapshot
                }
            }
            if Date() >= deadline {
                return latest
            }
            usleep(50_000)
        }
    }

    private func verdictForDecision(_ decision: String) -> Verdict {
        switch decision {
        case "matched": return .pass
        case "ambiguous": return .ambiguous
        case "missing": return .fail
        default: return .blocked
        }
    }

    private func printFocusedWindowBridge(_ bridge: FocusedWindowBridgeRecord) {
        print("decision=\(bridge.decision) target='\(bridge.targetTitle)' reason=\(bridge.reason)")
        if let focused = bridge.focusedWindow {
            print("focused title='\(focused.title)' frame=\(focused.frame.map(rect) ?? "<nil>") titleMatches=\(bridge.titleMatches) frameDistance=\(bridge.frameDistance.map { String(format: "%.0f", $0) } ?? "<nil>")")
        } else {
            print("focused=<nil>")
        }
    }

    private func printFocusAction(_ action: FocusWindowActionRecord) {
        print("decision=\(action.decision) strategy=\(action.strategy) target='\(action.targetTitle)' action=\(action.action ?? "<none>") elapsedMS=\(action.elapsedMS) reason=\(action.reason)")
        if let pre = action.preFocusedWindow {
            print("preFocused title='\(pre.title)' frame=\(pre.frame.map(rect) ?? "<nil>")")
        } else {
            print("preFocused=<nil>")
        }
        if let post = action.postFocusedWindow {
            print("postFocused title='\(post.title)' frame=\(post.frame.map(rect) ?? "<nil>")")
        } else {
            print("postFocused=<nil>")
        }
        if let menu = action.menuCandidate {
            print("menuCandidate index=\(menu.index) title='\(menu.title)' reason=\(menu.reason)")
        } else {
            print("menuCandidate=<nil>")
        }
    }

    private func printFocusValidation(_ validation: FocusActionValidationRecord) {
        print("validation=\(validation.verdictRawValue) summary='\(validation.summary)'")
        print("  targetPresentInMenu=\(validation.targetPresentInMenu)")
        print("  targetPresentInAXWindows=\(validation.targetPresentInAXWindows)")
        print("  targetNonMinimizedInAXWindows=\(validation.targetNonMinimizedInAXWindows)")
        print("  focusedWindowMatchesTarget=\(validation.focusedWindowMatchesTarget)")
        print("  focusedWindowDecision=\(validation.focusedWindowDecision) reason='\(validation.focusedWindowReason)'")
    }

    private func printFocusTabAction(_ action: FocusTabActionRecord) {
        print("decision=\(action.decision) strategy=\(action.strategy) targetTab='\(action.requestedTabTitle)' action=\(action.action ?? "<none>") pressed=\(action.pressed) elapsedMS=\(action.elapsedMS) reason=\(action.reason)")
        print("preActive='\(action.preActiveTitle)' postActive='\(action.postActiveTitle ?? "<nil>")'")
        print("stateChangedToTarget=\(action.stateChangedToTarget) focusedTitleMatchesTarget=\(action.focusedTitleMatchesTarget)")
        if let pre = action.preFocusedWindow {
            print("preFocused title='\(pre.title)' frame=\(pre.frame.map(rect) ?? "<nil>")")
        } else {
            print("preFocused=<nil>")
        }
        if let post = action.postFocusedWindow {
            print("postFocused title='\(post.title)' frame=\(post.frame.map(rect) ?? "<nil>")")
        } else {
            print("postFocused=<nil>")
        }
        if let candidate = action.candidate {
            print("candidate role=\(candidate.role) label='\(candidate.label)' nearTop=\(candidate.nearTop) clickable=\(candidate.clickable) frame=\(candidate.frame.map(rect) ?? "<nil>") actions=[\(candidate.actions.joined(separator: ","))]")
        } else {
            print("candidate=<nil>")
        }
    }

    private func printFocusedTabsBridge(_ bridge: FocusedTabsBridgeRecord) {
        print("decision=\(bridge.decision) targetWindow='\(bridge.targetWindowTitle)' reason=\(bridge.reason)")
        print("focusedWindow decision=\(bridge.focusedWindowBridge.decision) reason=\(bridge.focusedWindowBridge.reason)")
        for item in bridge.tabMatches {
            print("[Tab \(item.persistedTab.index)] decision=\(item.decision) title='\(item.persistedTab.title)' reason=\(item.reason)")
            for candidate in item.candidates {
                print("  - ax[\(candidate.index)] score=\(candidate.score) selected=\(candidate.selected.map(String.init) ?? "<nil>") title='\(candidate.title)' reason=\(candidate.reason)")
            }
        }
    }

    private func printTabObservationBridge(_ bridge: TabObservationBridgeRecord) {
        print("decision=\(bridge.decision) targetWindow='\(bridge.targetWindowTitle)' reason=\(bridge.reason)")
        print("focusedWindow decision=\(bridge.focusedWindowBridge.decision) reason=\(bridge.focusedWindowBridge.reason)")
        print("axCandidates=\(bridge.axCandidates.count) clickable=\(bridge.axCandidates.filter(\.clickable).count) nearTop=\(bridge.axCandidates.filter(\.nearTop).count)")
        for item in bridge.tabMatches {
            print("[Tab \(item.persistedTab.index)] decision=\(item.decision) title='\(item.persistedTab.title)' reason=\(item.reason)")
            for candidate in item.candidates.prefix(8) {
                print("  - ax[\(candidate.index)] depth=\(candidate.depth) role=\(candidate.role) labelSource=\(candidate.labelSource) nearTop=\(candidate.nearTop) clickable=\(candidate.clickable) selected=\(candidate.selected.map(String.init) ?? "<nil>") frame=\(candidate.frame.map(rect) ?? "<nil>") actions=[\(candidate.actions.joined(separator: ","))]")
            }
        }
        let unmatched = bridge.axCandidates.filter { candidate in
            !bridge.tabMatches.contains { item in
                normalize(item.persistedTab.title) == normalize(candidate.label)
            }
        }
        print("unmatchedCandidatesSample=\(min(unmatched.count, 20))/\(unmatched.count)")
        for candidate in unmatched.prefix(20) {
            print("  - ax[\(candidate.index)] role=\(candidate.role) label='\(candidate.label)' nearTop=\(candidate.nearTop) clickable=\(candidate.clickable) frame=\(candidate.frame.map(rect) ?? "<nil>")")
        }
    }

    private struct ButtonLikeRecord: Codable {
        let depth: Int
        let role: String
        let title: String
        let value: String?
        let frame: RectRecord?
        let actions: [String]
    }

    private func summarizeRoles(root: AXElementV2, maxDepth: Int) -> [String: Int] {
        var counts: [String: Int] = [:]
        walkAX(root: root, maxDepth: maxDepth) { element, _ in
            counts[element.role(), default: 0] += 1
        }
        return counts
    }

    private func collectButtonLike(root: AXElementV2, maxDepth: Int) -> [ButtonLikeRecord] {
        var records: [ButtonLikeRecord] = []
        walkAX(root: root, maxDepth: maxDepth) { element, depth in
            let role = element.role()
            let actions = element.actions()
            if role.contains("Button") || role == "AXTab" || actions.contains("AXPress") {
                records.append(ButtonLikeRecord(
                    depth: depth,
                    role: role,
                    title: element.title(),
                    value: element.valueString(),
                    frame: element.frame().map(RectRecord.init),
                    actions: actions
                ))
            }
        }
        return records
    }

    private func walkAX(root: AXElementV2, maxDepth: Int, visit: (AXElementV2, Int) -> Void) {
        var queue: [(AXElementV2, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visit(element, depth)
            if depth >= maxDepth { continue }
            for child in element.children() {
                queue.append((child, depth + 1))
            }
        }
    }
}

let command = V2CommandParser.parse(CommandLine.arguments)
exit(V2Runner().run(command))
