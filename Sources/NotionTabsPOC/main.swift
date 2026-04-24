import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum Command {
    case help
    case invalid(message: String)
    case status(prompt: Bool)
    case list
    case persistedList
    case persistedWatch(intervalMS: Int)
    case dump(depth: Int)
    case activate(window: Int, tab: Int)
    case activateWindowPersisted(window: Int, pauseMS: Int, strategy: ActivationStrategy)
    case activatePersisted(window: Int, tab: Int, pauseMS: Int, strategy: ActivationStrategy)
    case repeatActivatePersisted(window: Int, tab: Int, repeats: Int, pauseMS: Int, strategy: ActivationStrategy)
    case activateTarget(windowTitle: String, tabTitle: String, pauseMS: Int, strategy: ActivationStrategy)
    case probe(window: Int, raw: Bool)
    case verify(window: Int, range: ClosedRange<Int>?, pauseMS: Int, raw: Bool)
    case verifyList(repeats: Int, pauseMS: Int, raw: Bool)
    case windowSources
    case windowMap
    case menuTabs
    case inspectFocusedWindow
    case inspectWindowMenu
}

enum ActivationStrategy: String {
    case menuOnly = "menu-only"
    case appFirst = "app-first"
}

struct WindowActivationSummary {
    let strategy: ActivationStrategy
    let resolvedWindowTitle: String
    let appActivationAttempted: Bool
    let appActivationSucceeded: Bool
    let menuAction: String
    let raiseAction: String?
    let focusedWindowTitle: String
    let matchedWindow: Bool
    let elapsedMS: Int
}

struct AXFocusedTabState {
    let titles: [String]
    let selectedIndex: Int?
    let targetIndex: Int?
}

struct TabActivationAttempt {
    let action: String?
    let finalFocusedWindowTitle: String
    let matchedTab: Bool
    let trace: [String]
}

struct CommandParser {
    static func parse(arguments: [String]) -> Command {
        guard arguments.count >= 2 else { return .help }
        let cmd = arguments[1]

        switch cmd {
        case "status":
            return .status(prompt: arguments.contains("--prompt"))
        case "list":
            return .list
        case "persisted-list":
            return .persistedList
        case "persisted-watch":
            let intervalMS = parseInt(arguments: arguments, flag: "--interval-ms") ?? 1000
            return .persistedWatch(intervalMS: max(100, intervalMS))
        case "dump":
            let depth = parseInt(arguments: arguments, flag: "--depth") ?? 6
            return .dump(depth: max(1, depth))
        case "activate":
            guard
                let window = parseInt(arguments: arguments, flag: "--window"),
                let tab = parseInt(arguments: arguments, flag: "--tab")
            else {
                return .help
            }
            return .activate(window: window, tab: tab)
        case "activate-window-persisted":
            if arguments.contains("--tab") {
                return .invalid(message: "activate-window-persisted does not accept --tab. Use activate-persisted for window + tab activation.")
            }
            guard let window = parseInt(arguments: arguments, flag: "--window") else {
                return .help
            }
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 700
            let strategy = parseStrategy(arguments: arguments)
            return .activateWindowPersisted(window: window, pauseMS: max(50, pauseMS), strategy: strategy)
        case "activate-persisted":
            guard
                let window = parseInt(arguments: arguments, flag: "--window"),
                let tab = parseInt(arguments: arguments, flag: "--tab")
            else {
                return .help
            }
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 700
            let strategy = parseStrategy(arguments: arguments)
            return .activatePersisted(window: window, tab: tab, pauseMS: max(50, pauseMS), strategy: strategy)
        case "repeat-activate-persisted":
            guard
                let window = parseInt(arguments: arguments, flag: "--window"),
                let tab = parseInt(arguments: arguments, flag: "--tab")
            else {
                return .help
            }
            let repeats = parseInt(arguments: arguments, flag: "--repeats") ?? 5
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 700
            let strategy = parseStrategy(arguments: arguments)
            return .repeatActivatePersisted(window: window, tab: tab, repeats: max(1, repeats), pauseMS: max(50, pauseMS), strategy: strategy)
        case "activate-target":
            guard
                let windowTitle = parseString(arguments: arguments, flag: "--window-title"),
                let tabTitle = parseString(arguments: arguments, flag: "--tab-title")
            else {
                return .help
            }
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 500
            let strategy = parseStrategy(arguments: arguments)
            return .activateTarget(windowTitle: windowTitle, tabTitle: tabTitle, pauseMS: max(50, pauseMS), strategy: strategy)
        case "probe":
            let window = parseInt(arguments: arguments, flag: "--window") ?? 1
            let raw = arguments.contains("--raw")
            return .probe(window: window, raw: raw)
        case "verify":
            let window = parseInt(arguments: arguments, flag: "--window") ?? 1
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 350
            let raw = arguments.contains("--raw")
            let range = parseRange(arguments: arguments, flag: "--range")
            return .verify(window: window, range: range, pauseMS: max(50, pauseMS), raw: raw)
        case "verify-list":
            let repeats = parseInt(arguments: arguments, flag: "--repeats") ?? 2
            let pauseMS = parseInt(arguments: arguments, flag: "--pause-ms") ?? 350
            let raw = arguments.contains("--raw")
            return .verifyList(repeats: max(1, repeats), pauseMS: max(50, pauseMS), raw: raw)
        case "window-sources":
            return .windowSources
        case "window-map":
            return .windowMap
        case "menu-tabs":
            return .menuTabs
        case "inspect-focused-window":
            return .inspectFocusedWindow
        case "inspect-window-menu":
            return .inspectWindowMenu
        default:
            return .help
        }
    }

    private static func parseInt(arguments: [String], flag: String) -> Int? {
        guard let idx = arguments.firstIndex(of: flag), arguments.indices.contains(idx + 1) else {
            return nil
        }
        return Int(arguments[idx + 1])
    }

    private static func parseString(arguments: [String], flag: String) -> String? {
        guard let idx = arguments.firstIndex(of: flag), arguments.indices.contains(idx + 1) else {
            return nil
        }
        return arguments[idx + 1]
    }

    private static func parseRange(arguments: [String], flag: String) -> ClosedRange<Int>? {
        guard let idx = arguments.firstIndex(of: flag), arguments.indices.contains(idx + 1) else {
            return nil
        }
        let text = arguments[idx + 1]
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) else {
            return nil
        }
        if start <= end { return start ... end }
        return end ... start
    }

    private static func parseStrategy(arguments: [String]) -> ActivationStrategy {
        guard
            let idx = arguments.firstIndex(of: "--strategy"),
            arguments.indices.contains(idx + 1),
            let strategy = ActivationStrategy(rawValue: arguments[idx + 1])
        else {
            return .menuOnly
        }
        return strategy
    }
}

struct VerifiedWindowRecord: Equatable {
    let menuTitle: String
    let focusedWindowTitle: String
    let tabTitles: [String]
}

struct Runner {
    private let locator = NotionAppLocator()
    private let permissionManager = PermissionManager()
    private let windowScanner = NotionWindowScanner()
    private let windowServerScanner = NotionWindowServerScanner()
    private let shareableWindowScanner = NotionShareableWindowScanner()
    private let persistedStateScanner = NotionPersistedStateScanner()
    private let tabScanner = NotionTabScanner()

    func run(command: Command) -> Int32 {
        switch command {
        case .help:
            printHelp()
            return 0
        case let .invalid(message):
            Logger.error(message)
            print("")
            printHelp()
            return 1
        case let .status(prompt):
            return runStatus(prompt: prompt)
        case .list:
            return runList()
        case .persistedList:
            return runPersistedList()
        case let .persistedWatch(intervalMS):
            return runPersistedWatch(intervalMS: intervalMS)
        case let .dump(depth):
            return runDump(depth: depth)
        case let .activate(window, tab):
            return runActivate(window: window, tab: tab)
        case let .activateWindowPersisted(window, pauseMS, strategy):
            return runActivateWindowPersisted(window: window, pauseMS: pauseMS, strategy: strategy)
        case let .activatePersisted(window, tab, pauseMS, strategy):
            return runActivatePersisted(window: window, tab: tab, pauseMS: pauseMS, strategy: strategy)
        case let .repeatActivatePersisted(window, tab, repeats, pauseMS, strategy):
            return runRepeatActivatePersisted(window: window, tab: tab, repeats: repeats, pauseMS: pauseMS, strategy: strategy)
        case let .activateTarget(windowTitle, tabTitle, pauseMS, strategy):
            return runActivateTarget(windowTitle: windowTitle, tabTitle: tabTitle, pauseMS: pauseMS, strategy: strategy)
        case let .probe(window, raw):
            return runProbe(window: window, raw: raw)
        case let .verify(window, range, pauseMS, raw):
            return runVerify(window: window, range: range, pauseMS: pauseMS, raw: raw)
        case let .verifyList(repeats, pauseMS, raw):
            return runVerifyList(repeats: repeats, pauseMS: pauseMS, raw: raw)
        case .windowSources:
            return runWindowSources()
        case .windowMap:
            return runWindowMap()
        case .menuTabs:
            return runMenuTabs()
        case .inspectFocusedWindow:
            return runInspectFocusedWindow()
        case .inspectWindowMenu:
            return runInspectWindowMenu()
        }
    }

    private func printHelp() {
        let usage = """
        notion-tabs-poc commands:
          status [--prompt]              Show Notion process and Accessibility permission status
          list                           List Notion windows and tabs
          persisted-list                 Print passive window/tab snapshot from Notion state.json
          persisted-watch [--interval-ms N]
                                         Poll Notion state.json and print snapshots when it changes
          dump [--depth N]               Dump Notion accessibility tree (default depth: 6)
          activate --window N --tab M    Activate a specific tab by index
          activate-window-persisted --window N [--pause-ms N] [--strategy S]
                                         Activate only the target window from persisted snapshot index
          activate-persisted --window N --tab M [--pause-ms N] [--strategy S]
                                         Activate a window/tab by persisted snapshot index
          repeat-activate-persisted --window N --tab M [--repeats N] [--pause-ms N] [--strategy S]
                                         Repeat persisted activation and summarize success/timing
          activate-target --window-title T --tab-title T [--pause-ms N] [--strategy S]
                                         Activate a specific window and tab by title
          probe [--window N] [--raw]     Print candidate details (role/actions/frame/selected)
          verify [--window N] [--range A-B] [--pause-ms N] [--raw]
                                         Activate candidates in sequence and report behavior
          verify-list [--repeats N] [--pause-ms N] [--raw]
                                         Verify window/tab list reading via Window menu traversal
          window-sources                 Compare AX, Window menu, and Quartz window discovery
          window-map                     Match persisted windows against live CG/SC candidates
          menu-tabs                      Print items from Notion's Window menu
          inspect-focused-window         Print focused window attributes and id candidates
          inspect-window-menu            Print Window menu item attributes and id candidates

        activation strategies:
          menu-only                      Baseline: select target from Notion's Window menu only
          app-first                      First ask macOS to activate Notion, then select Window menu item
        """
        print(usage)
    }

    private func resolveNotion() -> NotionAppInstance? {
        guard let notion = locator.findRunningNotion() else {
            Logger.error("Notion app is not running.")
            return nil
        }
        return notion
    }

    private func runStatus(prompt: Bool) -> Int32 {
        if prompt {
            permissionManager.requestAccessibilityPermissionPrompt()
        }

        let trusted = permissionManager.isAccessibilityTrusted
        Logger.info("Accessibility trusted: \(trusted)")

        if let notion = locator.findRunningNotion() {
            Logger.info("Notion found: pid=\(notion.pid), bundleID=\(notion.bundleIdentifier ?? "unknown")")
        } else {
            Logger.warn("Notion is not currently running.")
        }
        return trusted ? 0 : 1
    }

    private func runList() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let windows = windowScanner.scanWindows(appElement: appElement)
        if windows.isEmpty {
            Logger.warn("No Notion windows found through Accessibility API.")
            let attrs = appElement.attributeNames()
            Logger.warn("Available app attributes: \(attrs.joined(separator: ", "))")
            return 1
        }

        print("Windows detected: \(windows.count)")
        for window in windows {
            print("[Window \(window.index)] \(window.title)")
            print("  tabCount=\(window.tabs.count)")
            if window.tabs.isEmpty {
                print("  (no tab candidates found)")
                continue
            }
            for tab in window.tabs {
                print("  [\(tab.index)] \(tab.title)")
            }
        }
        return 0
    }

    private func runPersistedList() -> Int32 {
        guard resolveNotion() != nil else { return 1 }
        do {
            let snapshot = try persistedStateScanner.loadSnapshot()
            printPersistedSnapshot(snapshot)
            return 0
        } catch {
            Logger.error("\(error)")
            return 1
        }
    }

    private func runPersistedWatch(intervalMS: Int) -> Int32 {
        guard resolveNotion() != nil else { return 1 }
        var lastPrintedSignature: String?

        while true {
            do {
                let snapshot = try persistedStateScanner.loadSnapshot()
                let signature = persistedSignature(snapshot)
                if signature != lastPrintedSignature {
                    printPersistedSnapshot(snapshot)
                    print("")
                    lastPrintedSignature = signature
                }
            } catch {
                Logger.error("\(error)")
                return 1
            }
            usleep(useconds_t(intervalMS * 1000))
        }
    }

    private func runDump(depth: Int) -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let dumper = AXTreeDumper(maxDepth: depth)
        print(dumper.dump(element: appElement))
        if let focusedWindow = appElement.focusedWindow() {
            print("\n===== AXFocusedWindow =====")
            print(dumper.dump(element: focusedWindow))
        } else {
            Logger.warn("AXFocusedWindow not available.")
        }
        return 0
    }

    private func runActivate(window: Int, tab: Int) -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let windows = windowScanner.scanWindows(appElement: appElement)
        let activator = NotionTabActivator()

        do {
            let usedAction = try activator.activate(
                notionApp: notion.runningApplication,
                windows: windows,
                windowIndex: window,
                tabIndex: tab
            )
            Logger.info("Activated Notion window \(window), tab \(tab), action=\(usedAction).")
            return 0
        } catch {
            Logger.error("\(error)")
            return 1
        }
    }

    private func runActivateWindowPersisted(window: Int, pauseMS: Int, strategy: ActivationStrategy) -> Int32 {
        guard resolveNotion() != nil else { return 1 }
        do {
            let snapshot = try persistedStateScanner.loadSnapshot()
            guard let targetWindow = snapshot.windows.first(where: { $0.index == window }) else {
                Logger.error("Persisted window index out of range: \(window)")
                return 1
            }

            let latestWindow = latestPersistedWindow(windowID: targetWindow.windowID) ?? targetWindow
            print("Activate-window-persisted request:")
            print("windowIndex=\(window) windowID='\(sanitize(latestWindow.windowID))' activeWindowTitle='\(sanitize(latestWindow.activeTitle))' frame=\(formatRect(latestWindow.bounds)) strategy=\(strategy.rawValue)")

            guard let summary = activateWindowByTitle(
                windowTitle: latestWindow.activeTitle,
                tabTitle: latestWindow.activeTitle,
                pauseMS: pauseMS,
                strategy: strategy,
                windowTitleCandidates: dedupeTitles([latestWindow.activeTitle]),
                expectedBounds: latestWindow.bounds
            ) else {
                return 1
            }

            printWindowActivationSummary(summary, requestedWindowTitle: latestWindow.activeTitle)
            return summary.matchedWindow ? 0 : 1
        } catch {
            Logger.error("\(error)")
            return 1
        }
    }

    private func runActivatePersisted(window: Int, tab: Int, pauseMS: Int, strategy: ActivationStrategy) -> Int32 {
        guard resolveNotion() != nil else { return 1 }
        do {
            let snapshot = try persistedStateScanner.loadSnapshot()
            guard let targetWindow = snapshot.windows.first(where: { $0.index == window }) else {
                Logger.error("Persisted window index out of range: \(window)")
                return 1
            }
            guard let targetTab = targetWindow.tabs.first(where: { $0.index == tab }) else {
                Logger.error("Persisted tab index out of range: window=\(window) tab=\(tab)")
                return 1
            }

            let latestWindow = latestPersistedWindow(windowID: targetWindow.windowID) ?? targetWindow
            let latestTab = latestWindow.tabs.first(where: { $0.tabID == targetTab.tabID }) ?? targetTab
            let activeTabIndex = latestWindow.tabs.first(where: { sanitize($0.title) == sanitize(latestWindow.activeTitle) })?.index

            print("Activate-persisted request:")
            print("windowIndex=\(window) windowID='\(sanitize(latestWindow.windowID))' activeWindowTitle='\(sanitize(latestWindow.activeTitle))' frame=\(formatRect(latestWindow.bounds)) strategy=\(strategy.rawValue)")
            print("tabIndex=\(tab) tabID='\(sanitize(latestTab.tabID))' tabTitle='\(sanitize(latestTab.title))'")

            return runActivateTarget(
                windowTitle: latestWindow.activeTitle,
                tabTitle: latestTab.title,
                pauseMS: pauseMS,
                strategy: strategy,
                windowTitleCandidates: dedupeTitles([latestWindow.activeTitle]),
                expectedBounds: latestWindow.bounds,
                activeTabIndex: activeTabIndex,
                targetTabIndex: latestTab.index
            )
        } catch {
            Logger.error("\(error)")
            return 1
        }
    }

    private func runRepeatActivatePersisted(
        window: Int,
        tab: Int,
        repeats: Int,
        pauseMS: Int,
        strategy: ActivationStrategy
    ) -> Int32 {
        var passCount = 0
        var durations: [Int] = []

        print("Repeat-activate-persisted start: window=\(window) tab=\(tab) repeats=\(repeats) pauseMS=\(pauseMS) strategy=\(strategy.rawValue)")
        for runIndex in 1 ... repeats {
            let start = CFAbsoluteTimeGetCurrent()
            let result = runActivatePersisted(window: window, tab: tab, pauseMS: pauseMS, strategy: strategy)
            let elapsed = elapsedMilliseconds(since: start)
            durations.append(elapsed)
            let passed = result == 0
            if passed { passCount += 1 }
            print("[\(runIndex)] \(passed ? "PASS" : "FAIL") total=\(elapsed)ms")
        }

        let minMS = durations.min() ?? 0
        let maxMS = durations.max() ?? 0
        let avgMS = durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count
        print("Repeat-activate-persisted summary: pass=\(passCount)/\(repeats) avg=\(avgMS)ms min=\(minMS)ms max=\(maxMS)ms")
        return passCount == repeats ? 0 : 1
    }

    private func runActivateTarget(
        windowTitle: String,
        tabTitle: String,
        pauseMS: Int,
        strategy: ActivationStrategy,
        windowTitleCandidates: [String] = [],
        expectedBounds: CGRect? = nil,
        activeTabIndex: Int? = nil,
        targetTabIndex: Int? = nil
    ) -> Int32 {
        let start = CFAbsoluteTimeGetCurrent()
        guard let summary = activateWindowByTitle(
            windowTitle: windowTitle,
            tabTitle: tabTitle,
            pauseMS: pauseMS,
            strategy: strategy,
            windowTitleCandidates: windowTitleCandidates,
            expectedBounds: expectedBounds
        ) else {
            return 1
        }
        printWindowActivationSummary(summary, requestedWindowTitle: windowTitle)
        guard summary.matchedWindow else {
            Logger.error("Target window activation did not land on the expected window.")
            return 1
        }

        guard let notion = requireReadyNotion() else { return 1 }
        let focusedApp = AXElement.applicationElement(pid: notion.pid)
        guard let focusedWindow = focusedApp.focusedWindow() else {
            Logger.error("No focused Notion window after window activation.")
            return 1
        }

        let focusedTitle = sanitize(focusedWindow.title())
        let axTabStateBefore = focusedTabState(pid: notion.pid, targetTabTitle: tabTitle)
        let firstAttempt = attemptTabActivation(
            pid: notion.pid,
            expectedWindowTitle: focusedTitle,
            tabTitle: tabTitle,
            timeoutMS: pauseMS
        )

        let tabAction = firstAttempt.action ?? "<none>"
        let postFocusedTitle = firstAttempt.finalFocusedWindowTitle
        let matchedTab = firstAttempt.matchedTab || titleMatches(postFocusedTitle, tabTitle)
        let tabTrace = firstAttempt.trace

        if tabAction == "<none>" {
            let availableTabs = availableTabsForFocusedWindow(pid: notion.pid)
            Logger.error("Target tab not found after window activation: \(tabTitle)")
            print("Focused window='\(focusedTitle)' availableTabs=\(availableTabs.joined(separator: " | "))")
            return 1
        }
        let elapsedMS = elapsedMilliseconds(since: start)
        let axTabStateAfter = focusedTabState(pid: notion.pid, targetTabTitle: tabTitle)

        print("Activate-target summary:")
        print("strategy=\(strategy.rawValue) windowAction=\(summary.menuAction) tabAction=\(tabAction)")
        print("requestedWindow='\(sanitize(windowTitle))' resolvedMenuWindow='\(sanitize(summary.resolvedWindowTitle))' focusedWindow='\(focusedTitle)' matchedWindow=\(summary.matchedWindow)")
        print("requestedTab='\(sanitize(tabTitle))' finalFocusedWindow='\(postFocusedTitle)' matchedTab=\(matchedTab)")
        print("axTabs before count=\(axTabStateBefore.titles.count) selected=\(axTabStateBefore.selectedIndex.map(String.init) ?? "<none>") target=\(axTabStateBefore.targetIndex.map(String.init) ?? "<none>")")
        print("axTabs after count=\(axTabStateAfter.titles.count) selected=\(axTabStateAfter.selectedIndex.map(String.init) ?? "<none>") target=\(axTabStateAfter.targetIndex.map(String.init) ?? "<none>")")
        print("tabTrace:")
        for line in tabTrace {
            print("  - \(line)")
        }
        print("timing total=\(elapsedMS)ms window=\(summary.elapsedMS)ms")

        return (summary.matchedWindow && matchedTab) ? 0 : 1
    }

    private func runProbe(window: Int, raw: Bool) -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let windows = windowScanner.scanWindows(appElement: appElement)
        if windows.isEmpty {
            Logger.error("No windows found.")
            return 1
        }

        print("Detected windows:")
        let focusedTitle = appElement.focusedWindow()?.title() ?? "<none>"
        for item in windows {
            let marker = item.title == focusedTitle ? "*" : " "
            let frameText = formatRect(item.rawElement.frame())
            let actions = item.rawElement.actionNames().joined(separator: ",")
            print("  \(marker) [\(item.index)] title='\(item.title)' frame=\(frameText) actions=[\(actions)] tabs(stric)=\(item.tabs.count)")
        }

        guard let target = windows.first(where: { $0.index == window }) else {
            Logger.error("Window \(window) not found.")
            return 1
        }

        let candidates = tabScanner.scanTabs(in: target.rawElement, strict: !raw)
        print("\nCandidates for window \(window) (mode=\(raw ? "raw" : "strict")): \(candidates.count)")
        for tab in candidates {
            let role = tab.rawElement.role() ?? "<nil>"
            let value = sanitize(tab.rawElement.valueString())
            let frame = formatRect(tab.rawElement.frame())
            let actions = tab.rawElement.actionNames().joined(separator: ",")
            let selected = tab.isSelected ? "true" : "false"
            print("[\(tab.index)] title='\(sanitize(tab.title))' role=\(role) selected=\(selected) value='\(value)' frame=\(frame) actions=[\(actions)]")
        }
        return 0
    }

    private func runVerify(window: Int, range: ClosedRange<Int>?, pauseMS: Int, raw: Bool) -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let activator = NotionTabActivator()
        let pause = useconds_t(pauseMS * 1000)

        let baseWindows = windowScanner.scanWindows(appElement: AXElement.applicationElement(pid: notion.pid))
        guard let baseWindow = baseWindows.first(where: { $0.index == window }) else {
            Logger.error("Window \(window) not found.")
            return 1
        }
        let baseCandidates = tabScanner.scanTabs(in: baseWindow.rawElement, strict: !raw)
        if baseCandidates.isEmpty {
            Logger.error("No candidates found for window \(window).")
            return 1
        }

        let executionRange: ClosedRange<Int> = range ?? (1 ... baseCandidates.count)
        var successCount = 0
        var totalCount = 0
        print("Verify start: window=\(window), mode=\(raw ? "raw" : "strict"), range=\(executionRange), pauseMS=\(pauseMS)")

        for idx in executionRange {
            let beforeApp = AXElement.applicationElement(pid: notion.pid)
            let beforeTitle = beforeApp.focusedWindow()?.title() ?? "<none>"

            let freshWindows = windowScanner.scanWindows(appElement: beforeApp)
            guard let freshWindow = freshWindows.first(where: { $0.index == window }) else {
                print("[\(idx)] FAIL window disappeared")
                totalCount += 1
                continue
            }
            let freshCandidates = tabScanner.scanTabs(in: freshWindow.rawElement, strict: !raw)
            guard let tab = freshCandidates.first(where: { $0.index == idx }) else {
                print("[\(idx)] SKIP candidate missing")
                continue
            }

            totalCount += 1
            do {
                let action = try activator.activate(
                    notionApp: notion.runningApplication,
                    windows: [NotionWindowSnapshot(index: window, title: freshWindow.title, rawElement: freshWindow.rawElement, tabs: freshCandidates)],
                    windowIndex: window,
                    tabIndex: idx
                )
                usleep(pause)
                let afterApp = AXElement.applicationElement(pid: notion.pid)
                let afterTitle = afterApp.focusedWindow()?.title() ?? "<none>"
                let matched = titleMatches(afterTitle, tab.title)
                let changed = afterTitle != beforeTitle
                let passed = matched || changed
                if passed { successCount += 1 }
                let verdict = passed ? "PASS" : "FAIL"
                print("[\(idx)] \(verdict) action=\(action) tab='\(sanitize(tab.title))' before='\(sanitize(beforeTitle))' after='\(sanitize(afterTitle))' match=\(matched) changed=\(changed)")
            } catch {
                print("[\(idx)] FAIL error=\(error)")
            }
        }

        print("Verify summary: pass=\(successCount)/\(max(totalCount, 1))")
        return successCount > 0 ? 0 : 1
    }

    private func runMenuTabs() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)

        guard let items = windowMenuItems(appElement: appElement) else {
            return 1
        }
        if items.isEmpty {
            Logger.warn("No items found in Window menu.")
            return 1
        }

        print("Window menu items:")
        var idx = 1
        for item in items {
            let title = sanitize(item.title())
            let actions = item.actionNames().joined(separator: ",")
            let selected = item.isSelected() == true ? "true" : "false"
            print("[\(idx)] title='\(title)' selected=\(selected) actions=[\(actions)]")
            idx += 1
        }
        return 0
    }

    private func runWindowSources() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let axWindows = windowScanner.scanWindows(appElement: appElement)
        let cgWindows = windowServerScanner.scanWindows(pid: notion.pid)
        let shareableVisible = shareableWindowScanner.scanWindows(bundleIdentifier: notion.bundleIdentifier, onScreenOnly: true)
        let shareableAll = shareableWindowScanner.scanWindows(bundleIdentifier: notion.bundleIdentifier, onScreenOnly: false)
        let menuItems = windowMenuItems(appElement: appElement) ?? []
        let menuTitles = candidateWindowMenuItems(from: menuItems).map { sanitize($0.title()) }

        print("AX windows: \(axWindows.count)")
        for window in axWindows {
            print("[AX \(window.index)] title='\(sanitize(window.title))' frame=\(formatRect(window.rawElement.frame())) tabs=\(window.tabs.count)")
        }

        print("\nWindow menu titles: \(menuTitles.count)")
        for (idx, title) in menuTitles.enumerated() {
            print("[Menu \(idx + 1)] title='\(title)'")
        }

        print("\nQuartz window candidates: \(cgWindows.count)")
        for window in cgWindows {
            let onscreen = window.isOnscreen.map { $0 ? "true" : "false" } ?? "unknown"
            let title = sanitize(window.title)
            print("[CG \(window.index)] id=\(window.windowID) title='\(title)' frame=\(formatRect(window.bounds)) onscreen=\(onscreen) layer=\(window.layer) alpha=\(String(format: "%.2f", window.alpha))")
        }

        print("\nScreenCaptureKit windows (onscreen-only): \(shareableVisible.count)")
        for window in shareableVisible {
            print("[SC on \(window.index)] id=\(window.windowID) title='\(sanitize(window.title))' frame=\(formatRect(window.frame)) isOnScreen=\(window.isOnScreen) isActive=\(window.isActive)")
        }

        print("\nScreenCaptureKit windows (all): \(shareableAll.count)")
        for window in shareableAll {
            print("[SC all \(window.index)] id=\(window.windowID) title='\(sanitize(window.title))' frame=\(formatRect(window.frame)) isOnScreen=\(window.isOnScreen) isActive=\(window.isActive)")
        }

        return 0
    }

    private func runWindowMap() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        do {
            let snapshot = try persistedStateScanner.loadSnapshot()
            let cgWindows = windowServerScanner.scanWindows(pid: notion.pid)
            let scWindows = shareableWindowScanner.scanWindows(bundleIdentifier: notion.bundleIdentifier, onScreenOnly: false)

            print("Persisted -> live mapping:")
            for window in snapshot.windows {
                print("[Persisted \(window.index)] windowID='\(sanitize(window.windowID))' active='\(sanitize(window.activeTitle))' frame=\(formatRect(window.bounds))")
                if let cgMatch = bestWindowMatch(
                    persistedTitle: window.activeTitle,
                    persistedBounds: window.bounds,
                    liveWindows: cgWindows.map { LiveWindowCandidate(id: "\($0.windowID)", title: $0.title, frame: $0.bounds) }
                ) {
                    print("  CG match: id=\(cgMatch.id) title='\(sanitize(cgMatch.title))' frame=\(formatRect(cgMatch.frame)) score=\(cgMatch.score)")
                } else {
                    print("  CG match: <none>")
                }
                if let scMatch = bestWindowMatch(
                    persistedTitle: window.activeTitle,
                    persistedBounds: window.bounds,
                    liveWindows: scWindows.map { LiveWindowCandidate(id: "\($0.windowID)", title: $0.title, frame: $0.frame) }
                ) {
                    print("  SC match: id=\(scMatch.id) title='\(sanitize(scMatch.title))' frame=\(formatRect(scMatch.frame)) score=\(scMatch.score)")
                } else {
                    print("  SC match: <none>")
                }
            }
            return 0
        } catch {
            Logger.error("\(error)")
            return 1
        }
    }

    private func runInspectFocusedWindow() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        guard let focusedWindow = appElement.focusedWindow() else {
            Logger.error("No focused Notion window.")
            return 1
        }

        print("Focused window inspection:")
        print("title='\(sanitize(focusedWindow.title()))'")
        print("value='\(sanitize(focusedWindow.valueString()))'")
        print("role='\(sanitize(focusedWindow.role()))'")
        print("actions=[\(focusedWindow.actionNames().joined(separator: ","))]")
        print("frame=\(formatRect(focusedWindow.frame()))")
        print("attributes:")
        for name in focusedWindow.attributeNames().sorted() {
            let value = focusedWindow.attributeValue(name as CFString)
            print("  \(name)=\(describeAXValue(value))")
        }
        let parameterized = focusedWindow.parameterizedAttributeNames().sorted()
        if !parameterized.isEmpty {
            print("parameterizedAttributes=[\(parameterized.joined(separator: ", "))]")
        }
        return 0
    }

    private struct LiveWindowCandidate {
        let id: String
        let title: String?
        let frame: CGRect
    }

    private struct WindowMatch {
        let id: String
        let title: String
        let frame: CGRect
        let score: Int
    }

    private func bestWindowMatch(
        persistedTitle: String,
        persistedBounds: CGRect,
        liveWindows: [LiveWindowCandidate]
    ) -> WindowMatch? {
        let scored = liveWindows.compactMap { candidate -> WindowMatch? in
            let candidateTitle = sanitize(candidate.title)
            let titleScore = titleMatches(candidateTitle, persistedTitle) ? 0 : 100
            let frameScore = frameDistanceScore(persistedBounds, candidate.frame)
            let score = titleScore + frameScore
            return WindowMatch(id: candidate.id, title: candidateTitle, frame: candidate.frame, score: score)
        }
        return scored.min(by: { $0.score < $1.score })
    }

    private func frameDistanceScore(_ lhs: CGRect, _ rhs: CGRect) -> Int {
        let dx = abs(lhs.origin.x - rhs.origin.x)
        let dy = abs(lhs.origin.y - rhs.origin.y)
        let dw = abs(lhs.size.width - rhs.size.width)
        let dh = abs(lhs.size.height - rhs.size.height)
        return Int(dx + dy + dw + dh)
    }

    private func runInspectWindowMenu() -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let appElement = AXElement.applicationElement(pid: notion.pid)
        guard let items = windowMenuItems(appElement: appElement) else {
            return 1
        }

        let candidateItems = candidateWindowMenuItems(from: items)
        if candidateItems.isEmpty {
            Logger.warn("No candidate items found in Window menu.")
            return 1
        }

        print("Window menu inspection:")
        for (idx, item) in candidateItems.enumerated() {
            print("[\(idx + 1)] title='\(sanitize(item.title()))' role='\(sanitize(item.role()))' selected=\(item.isSelected() == true) actions=[\(item.actionNames().joined(separator: ","))]")
            print("  frame=\(formatRect(item.frame()))")
            print("  value='\(sanitize(item.valueString()))'")
            if let primary = item.attributeValue("AXMenuItemPrimaryUIElement" as CFString), CFGetTypeID(primary) == AXUIElementGetTypeID() {
                let primaryElement = AXElement(unsafeBitCast(primary, to: AXUIElement.self))
                print("  primaryUIElement title='\(sanitize(primaryElement.title()))' role='\(sanitize(primaryElement.role()))' frame=\(formatRect(primaryElement.frame()))")
            } else {
                print("  primaryUIElement=<nil>")
            }
            print("  attributes:")
            for name in item.attributeNames().sorted() {
                let value = item.attributeValue(name as CFString)
                print("    \(name)=\(describeAXValue(value))")
            }
        }
        return 0
    }

    private func runVerifyList(repeats: Int, pauseMS: Int, raw: Bool) -> Int32 {
        guard let notion = requireReadyNotion() else { return 1 }
        let pause = useconds_t(pauseMS * 1000)
        var baseline: [VerifiedWindowRecord]?
        var failures: [String] = []

        for runIndex in 1 ... repeats {
            let appElement = AXElement.applicationElement(pid: notion.pid)
            guard let menuItems = windowMenuItems(appElement: appElement) else { return 1 }
            let windowItems = candidateWindowMenuItems(from: menuItems)
            if windowItems.isEmpty {
                Logger.error("No candidate window items found in Window menu.")
                return 1
            }

            print("Run \(runIndex)/\(repeats): candidateWindows=\(windowItems.count)")
            var records: [VerifiedWindowRecord] = []

            for (offset, item) in windowItems.enumerated() {
                let menuTitle = sanitize(item.title())
                guard performMenuItemAction(item) != nil else {
                    let message = "run \(runIndex): failed to activate Window menu item '\(menuTitle)'"
                    failures.append(message)
                    print("  [\(offset + 1)] FAIL menuTitle='\(menuTitle)' reason=activation")
                    continue
                }

                usleep(pause)

                let focusedApp = AXElement.applicationElement(pid: notion.pid)
                guard let focusedWindow = focusedApp.focusedWindow() else {
                    let message = "run \(runIndex): no focused window after activating '\(menuTitle)'"
                    failures.append(message)
                    print("  [\(offset + 1)] FAIL menuTitle='\(menuTitle)' reason=no-focused-window")
                    continue
                }

                let tabs = tabScanner.scanTabs(in: focusedWindow, strict: !raw)
                let record = VerifiedWindowRecord(
                    menuTitle: menuTitle,
                    focusedWindowTitle: sanitize(focusedWindow.title()),
                    tabTitles: tabs.map(\.title)
                )
                records.append(record)

                let tabSummary = record.tabTitles.joined(separator: " | ")
                print("  [\(offset + 1)] PASS menuTitle='\(record.menuTitle)' focusedTitle='\(record.focusedWindowTitle)' tabs=\(record.tabTitles.count)")
                print("      \(tabSummary)")
            }

            let duplicateRecords = duplicateWindowRecords(in: records)
            if !duplicateRecords.isEmpty {
                failures.append("run \(runIndex): duplicated window snapshots: \(duplicateRecords.joined(separator: "; "))")
            }

            if let baseline {
                if baseline != records {
                    failures.append("run \(runIndex): snapshot changed from baseline")
                }
            } else {
                baseline = records
            }
        }

        if failures.isEmpty {
            print("Verify-list summary: PASS repeats=\(repeats)")
            return 0
        }

        print("Verify-list summary: FAIL repeats=\(repeats) issues=\(failures.count)")
        for failure in failures {
            print("  - \(failure)")
        }
        return 1
    }

    private func requireReadyNotion() -> NotionAppInstance? {
        guard permissionManager.isAccessibilityTrusted else {
            Logger.error("Accessibility permission is not granted. Run: notion-tabs-poc status --prompt")
            return nil
        }
        return resolveNotion()
    }

    private func formatRect(_ rect: CGRect?) -> String {
        guard let rect else { return "<nil>" }
        return String(format: "(x:%.0f,y:%.0f,w:%.0f,h:%.0f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    private func formatRect(_ rect: CGRect) -> String {
        String(format: "(x:%.0f,y:%.0f,w:%.0f,h:%.0f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    private func sanitize(_ text: String?) -> String {
        guard let text else { return "" }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    private func describeAXValue(_ value: AnyObject?) -> String {
        guard let value else { return "<nil>" }
        if let str = value as? String {
            return "\"\(sanitize(str))\""
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let array = value as? [AnyObject] {
            return "[\(array.count) items]"
        }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return "<AXUIElement>"
        }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeBitCast(value, to: AXValue.self)
            let type = AXValueGetType(axValue)
            switch type {
            case .cgPoint:
                var point = CGPoint.zero
                if AXValueGetValue(axValue, .cgPoint, &point) {
                    return String(format: "(x:%.0f,y:%.0f)", point.x, point.y)
                }
            case .cgSize:
                var size = CGSize.zero
                if AXValueGetValue(axValue, .cgSize, &size) {
                    return String(format: "(w:%.0f,h:%.0f)", size.width, size.height)
                }
            case .cgRect:
                var rect = CGRect.zero
                if AXValueGetValue(axValue, .cgRect, &rect) {
                    return formatRect(rect)
                }
            default:
                return "<AXValue \(type)>"
            }
        }
        return "<\(type(of: value))>"
    }

    private func printPersistedSnapshot(_ snapshot: NotionPersistedStateSnapshot) {
        print("Persisted snapshot:")
        if let modifiedAt = snapshot.modifiedAt {
            print("modifiedAt=\(formatDate(modifiedAt))")
        } else {
            print("modifiedAt=<unknown>")
        }
        print("windowCount=\(snapshot.windows.count)")

        for window in snapshot.windows {
            print("[Window \(window.index)] windowID='\(sanitize(window.windowID))' active='\(sanitize(window.activeTitle))' frame=\(formatRect(window.bounds)) tabCount=\(window.tabs.count)")
            for tab in window.tabs {
                let marker = tab.title == window.activeTitle ? "*" : " "
                print("  \(marker) [\(tab.index)] tabID='\(sanitize(tab.tabID))' \(sanitize(tab.title))")
            }
        }
    }

    private func persistedSignature(_ snapshot: NotionPersistedStateSnapshot) -> String {
        let modifiedAt = snapshot.modifiedAt?.timeIntervalSince1970 ?? 0
        let windows = snapshot.windows.map { window in
            let tabs = window.tabs.map(\.title).joined(separator: "|")
            return "\(window.activeTitle)|\(Int(window.bounds.origin.x))|\(Int(window.bounds.origin.y))|\(Int(window.bounds.width))|\(Int(window.bounds.height))|\(tabs)"
        }.joined(separator: "||")
        return "\(modifiedAt)||\(windows)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func windowMenuItems(appElement: AXElement) -> [AXElement]? {
        guard let menuBar = appElement.children().first(where: { $0.role() == "AXMenuBar" }) else {
            Logger.error("AXMenuBar not found.")
            return nil
        }
        guard let windowItem = menuBar.children().first(where: {
            $0.role() == "AXMenuBarItem" && ($0.title() ?? "") == "Window"
        }) else {
            Logger.error("'Window' menu item not found.")
            return nil
        }
        guard let menu = windowItem.children().first(where: { $0.role() == "AXMenu" }) else {
            Logger.error("Window menu container not found.")
            return nil
        }
        return menu.children().filter { $0.role() == "AXMenuItem" }
    }

    private func candidateWindowMenuItems(from items: [AXElement]) -> [AXElement] {
        var result: [AXElement] = []
        for item in items.reversed() {
            let title = sanitize(item.title())
            if title.isEmpty {
                if !result.isEmpty { break }
                continue
            }
            result.append(item)
        }
        return result.reversed()
    }

    private func findWindowMenuItem(_ items: [AXElement], title: String) -> AXElement? {
        items.first(where: { sanitize($0.title()) == title })
    }

    private func findTabSnapshot(_ tabs: [NotionTabSnapshot], title: String) -> NotionTabSnapshot? {
        tabs.first(where: { sanitize($0.title) == title })
    }

    private func resolveWindowMenuTitle(windowSelector: String) -> String? {
        guard let snapshot = try? persistedStateScanner.loadSnapshot() else { return nil }

        if let exact = snapshot.windows.first(where: { sanitize($0.activeTitle) == windowSelector }) {
            return exact.activeTitle
        }

        return nil
    }

    private func activateWindowByTitle(
        windowTitle: String,
        tabTitle: String,
        pauseMS: Int,
        strategy: ActivationStrategy,
        windowTitleCandidates: [String],
        expectedBounds: CGRect?
    ) -> WindowActivationSummary? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let notion = requireReadyNotion() else { return nil }
        var appActivationAttempted = false
        var appActivationSucceeded = false
        let appElement = AXElement.applicationElement(pid: notion.pid)
        let preActivationWindows = windowScanner.scanWindows(appElement: appElement)

        if strategy == .appFirst {
            appActivationAttempted = true
            let unhid = notion.runningApplication.unhide()
            let activated = notion.runningApplication.activate(options: [.activateAllWindows])
            appActivationSucceeded = unhid || activated

            if titleMatches(windowTitle, tabTitle),
               let directSummary = activateWindowFromAXIfPossible(
                   pid: notion.pid,
                   strategy: strategy,
                   expectedBounds: expectedBounds,
                   windowTitle: windowTitle,
                   windowTitleCandidates: windowTitleCandidates,
                   preActivationWindows: preActivationWindows,
                   start: start,
                   appActivationAttempted: appActivationAttempted,
                   appActivationSucceeded: appActivationSucceeded
               )
            {
                return directSummary
            }
        }

        guard let menuItems = windowMenuItems(appElement: AXElement.applicationElement(pid: notion.pid)) else { return nil }
        let candidateItems = candidateWindowMenuItems(from: menuItems)
        let targetMenuItems = resolveTargetMenuItems(
            candidateItems: candidateItems,
            windowTitle: windowTitle,
            fallbackTitles: windowTitleCandidates
        )
        if targetMenuItems.isEmpty {
            let menuTitles = candidateItems.map { sanitize($0.title()) }
            Logger.error("Target window not found in Window menu.")
            print("Requested window='\(sanitize(windowTitle))' tab='\(sanitize(tabTitle))'")
            print("Tried titles=\(dedupeTitles([windowTitle] + windowTitleCandidates).joined(separator: " | "))")
            print("Available menu titles=\(menuTitles.joined(separator: " | "))")
            return nil
        }

        var lastSummary: WindowActivationSummary?
        for targetMenuItem in targetMenuItems {
            let resolvedWindowTitle = sanitize(targetMenuItem.title())

            guard let menuAction = performMenuItemAction(targetMenuItem) else {
                Logger.error("Failed to activate target window from Window menu: \(resolvedWindowTitle)")
                continue
            }

            let focusedAfterMenu = waitForFocusedWindowTitle(
                pid: notion.pid,
                timeoutMS: pauseMS
            ) { title in
                self.titleMatches(title, resolvedWindowTitle)
            }

            let focusedApp = AXElement.applicationElement(pid: notion.pid)
            guard let focusedWindow = focusedApp.focusedWindow() else {
                Logger.error("No focused Notion window after selecting Window menu item.")
                continue
            }

            let raiseAction = strategy == .menuOnly ? performRaiseActionIfAvailable(focusedWindow) : nil
            if raiseAction != nil, focusedAfterMenu == nil {
                _ = waitForFocusedWindowTitle(
                    pid: notion.pid,
                    timeoutMS: pauseMS
                ) { title in
                    self.titleMatches(title, resolvedWindowTitle)
                }
            }

            let refreshedFocusedWindow = AXElement.applicationElement(pid: notion.pid).focusedWindow()
            let focusedTitle = sanitize(refreshedFocusedWindow?.title())
            let focusedFrame = refreshedFocusedWindow?.frame()
            let frameMatch = expectedBounds.map { rectMatches($0, focusedFrame) } ?? nil
            let titleMatch = titleMatches(focusedTitle, resolvedWindowTitle)
            let shouldTrustTitleMore = isLikelyOffscreenBounds(expectedBounds)
            let matchedWindow = shouldTrustTitleMore ? titleMatch : (expectedBounds != nil ? (titleMatch && (frameMatch ?? false)) : titleMatch)

            let summary = WindowActivationSummary(
                strategy: strategy,
                resolvedWindowTitle: resolvedWindowTitle,
                appActivationAttempted: appActivationAttempted,
                appActivationSucceeded: appActivationSucceeded,
                menuAction: menuAction,
                raiseAction: raiseAction,
                focusedWindowTitle: focusedTitle,
                matchedWindow: matchedWindow,
                elapsedMS: elapsedMilliseconds(since: start)
            )
            lastSummary = summary

            if matchedWindow {
                return summary
            }
        }

        return lastSummary
    }

    private func activateWindowFromAXIfPossible(
        pid: pid_t,
        strategy: ActivationStrategy,
        expectedBounds: CGRect?,
        windowTitle: String,
        windowTitleCandidates: [String],
        preActivationWindows: [NotionWindowSnapshot],
        start: CFAbsoluteTime,
        appActivationAttempted: Bool,
        appActivationSucceeded: Bool
    ) -> WindowActivationSummary? {
        let titleCandidates = dedupeTitles([windowTitle] + windowTitleCandidates)
        let deadline = Date().addingTimeInterval(TimeInterval(900) / 1000.0)
        let pollUS = useconds_t(25_000)

        while true {
            let appElement = AXElement.applicationElement(pid: pid)
            let postActivationWindows = windowScanner.scanWindows(appElement: appElement)
            if let matchedWindow = findMatchingAXWindow(
                windows: postActivationWindows,
                titleCandidates: titleCandidates,
                expectedBounds: expectedBounds
            ) {
                let wasVisibleBefore = preActivationWindows.contains { prior in
                    prior.rawElement.isEqualTo(matchedWindow.rawElement)
                }
                let action = matchedWindow.rawElement.isSelected() == true ? "AXFocusedWindow" : (performRaiseActionIfAvailable(matchedWindow.rawElement) ?? "AXWindowMatch")
                let focusedTitle = waitForFocusedWindowTitle(
                    pid: pid,
                    timeoutMS: 250
                ) { title in
                    self.titleMatches(title, matchedWindow.title)
                } ?? sanitize(appElement.focusedWindow()?.title())
                let focusedFrame = appElement.focusedWindow()?.frame()
                let frameMatch = expectedBounds.map { rectMatches($0, focusedFrame) } ?? nil
                let titleMatch = titleMatches(focusedTitle, matchedWindow.title)
                let matched = expectedBounds != nil ? (titleMatch && (frameMatch ?? false)) : titleMatch

                if matched || wasVisibleBefore {
                    return WindowActivationSummary(
                        strategy: strategy,
                        resolvedWindowTitle: matchedWindow.title,
                        appActivationAttempted: appActivationAttempted,
                        appActivationSucceeded: appActivationSucceeded,
                        menuAction: action,
                        raiseAction: nil,
                        focusedWindowTitle: focusedTitle,
                        matchedWindow: matched,
                        elapsedMS: elapsedMilliseconds(since: start)
                    )
                }
            }

            if Date() >= deadline {
                return nil
            }
            usleep(pollUS)
        }
    }

    private func findMatchingAXWindow(
        windows: [NotionWindowSnapshot],
        titleCandidates: [String],
        expectedBounds: CGRect?
    ) -> NotionWindowSnapshot? {
        var scored: [(score: Int, window: NotionWindowSnapshot)] = []
        for window in windows {
            let candidateTitle = sanitize(window.title)
            let titleMatch = titleCandidates.contains { titleMatches(candidateTitle, $0) }
            let frameMatch = expectedBounds.map { rectMatches($0, window.rawElement.frame()) } ?? false
            guard titleMatch || frameMatch else { continue }

            let titleScore = titleMatch ? 0 : 100
            let frameScore = frameMatch ? 0 : 50
            scored.append((titleScore + frameScore, window))
        }

        return scored.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            let lhsX = $0.window.rawElement.frame()?.minX ?? .greatestFiniteMagnitude
            let rhsX = $1.window.rawElement.frame()?.minX ?? .greatestFiniteMagnitude
            return lhsX < rhsX
        }.first?.window
    }

    private func resolveTargetMenuItems(
        candidateItems: [AXElement],
        windowTitle: String,
        fallbackTitles: [String]
    ) -> [AXElement] {
        let preferred = resolveWindowMenuTitle(windowSelector: windowTitle)
        let titleCandidates = dedupeTitles([preferred, windowTitle] + fallbackTitles)
        var result: [AXElement] = []
        var seenIndexes: Set<Int> = []

        for candidate in titleCandidates where !candidate.isEmpty {
            for (index, item) in candidateItems.enumerated() {
                let menuTitle = sanitize(item.title())
                if menuTitle == candidate {
                    if seenIndexes.insert(index).inserted {
                        result.append(item)
                    }
                }
            }
        }
        return result
    }

    private func performMenuItemAction(_ item: AXElement) -> String? {
        let actions = item.actionNames()
        if actions.contains(kAXPressAction as String), item.performAction(kAXPressAction as CFString) {
            return kAXPressAction as String
        }
        if actions.contains(kAXPickAction as String), item.performAction(kAXPickAction as CFString) {
            return kAXPickAction as String
        }
        return nil
    }

    private func performRaiseActionIfAvailable(_ element: AXElement) -> String? {
        let actions = element.actionNames()
        if actions.contains(kAXRaiseAction as String), element.performAction(kAXRaiseAction as CFString) {
            return kAXRaiseAction as String
        }
        return nil
    }

    private func printWindowActivationSummary(_ summary: WindowActivationSummary, requestedWindowTitle: String) {
        print("Activate-window summary:")
        print("strategy=\(summary.strategy.rawValue) appActivationAttempted=\(summary.appActivationAttempted) appActivationSucceeded=\(summary.appActivationSucceeded)")
        print("menuAction=\(summary.menuAction) raiseAction=\(summary.raiseAction ?? "<none>")")
        print("requestedWindow='\(sanitize(requestedWindowTitle))' resolvedMenuWindow='\(sanitize(summary.resolvedWindowTitle))' focusedWindow='\(summary.focusedWindowTitle)' matchedWindow=\(summary.matchedWindow)")
        print("timing window=\(summary.elapsedMS)ms")
    }

    private func waitForFocusedWindowTitle(pid: pid_t, timeoutMS: Int, matches: (String) -> Bool) -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        let pollUS = useconds_t(25_000)

        while true {
            let title = sanitize(AXElement.applicationElement(pid: pid).focusedWindow()?.title())
            if !title.isEmpty, matches(title) {
                return title
            }
            if Date() >= deadline {
                return !title.isEmpty ? title : nil
            }
            usleep(pollUS)
        }
    }

    private func waitForTab(pid: pid_t, expectedWindowTitle: String?, title: String, timeoutMS: Int) -> NotionTabSnapshot? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        let pollUS = useconds_t(25_000)

        while true {
            guard let window = AXElement.applicationElement(pid: pid).focusedWindow() else {
                if Date() >= deadline {
                    return nil
                }
                usleep(pollUS)
                continue
            }

            if let expectedWindowTitle {
                let currentTitle = sanitize(window.title())
                if !currentTitle.isEmpty && !titleMatches(currentTitle, expectedWindowTitle) {
                    if Date() >= deadline {
                        return nil
                    }
                    usleep(pollUS)
                    continue
                }
            }

            let exactTabs = tabScanner.scanTabs(in: window, strict: true)
            let rawTabs = tabScanner.scanTabs(in: window, strict: false)
            let tabs = exactTabs.isEmpty ? rawTabs : exactTabs
            if let match = findTabSnapshot(tabs, title: title) {
                return match
            }
            if Date() >= deadline {
                return nil
            }
            usleep(pollUS)
        }
    }

    private func attemptTabActivation(
        pid: pid_t,
        expectedWindowTitle: String,
        tabTitle: String,
        timeoutMS: Int
    ) -> TabActivationAttempt {
        guard let targetTab = waitForTab(
            pid: pid,
            expectedWindowTitle: expectedWindowTitle,
            title: tabTitle,
            timeoutMS: timeoutMS
        ) else {
            let title = sanitize(AXElement.applicationElement(pid: pid).focusedWindow()?.title())
            return TabActivationAttempt(
                action: nil,
                finalFocusedWindowTitle: title,
                matchedTab: false,
                trace: ["ax direct: target tab not visible in AX"]
            )
        }

        var trace = ["ax direct: found target tab"]
        let action = performTabActivationActions(targetTab.rawElement)
        trace.append("ax direct: action=\(action ?? "<none>")")
        let confirmation = waitForTabActivationConfirmation(
            pid: pid,
            expectedWindowTitle: expectedWindowTitle,
            tabTitle: tabTitle,
            timeoutMS: timeoutMS
        )
        if confirmation.matchedTab {
            trace.append("ax direct: matched -> '\(sanitize(confirmation.finalFocusedWindowTitle))'")
            return TabActivationAttempt(
                action: action,
                finalFocusedWindowTitle: confirmation.finalFocusedWindowTitle,
                matchedTab: true,
                trace: trace
            )
        }
        trace.append("ax direct: failed -> '\(sanitize(confirmation.finalFocusedWindowTitle))'")
        return TabActivationAttempt(
            action: action,
            finalFocusedWindowTitle: confirmation.finalFocusedWindowTitle,
            matchedTab: false,
            trace: trace
        )
    }

    private func performTabActivationActions(_ element: AXElement) -> String? {
        let actions = element.actionNames()
        var usedActions: [String] = []

        if actions.contains("AXScrollToVisible"), element.performAction("AXScrollToVisible" as CFString) {
            usedActions.append("AXScrollToVisible")
        }
        if actions.contains(kAXPressAction as String), element.performAction(kAXPressAction as CFString) {
            usedActions.append(kAXPressAction as String)
        } else if actions.contains(kAXPickAction as String), element.performAction(kAXPickAction as CFString) {
            usedActions.append(kAXPickAction as String)
        }

        return usedActions.isEmpty ? nil : usedActions.joined(separator: ",")
    }

    private func waitForTabActivationConfirmation(
        pid: pid_t,
        expectedWindowTitle: String,
        tabTitle: String,
        timeoutMS: Int
    ) -> (finalFocusedWindowTitle: String, matchedTab: Bool) {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        let pollUS = useconds_t(25_000)
        var lastFocusedTitle = sanitize(AXElement.applicationElement(pid: pid).focusedWindow()?.title())

        while true {
            let app = AXElement.applicationElement(pid: pid)
            if let focusedWindow = app.focusedWindow() {
                lastFocusedTitle = sanitize(focusedWindow.title())
                if titleMatches(lastFocusedTitle, tabTitle) {
                    return (lastFocusedTitle, true)
                }

                if titleMatches(lastFocusedTitle, expectedWindowTitle) {
                    let exactTabs = tabScanner.scanTabs(in: focusedWindow, strict: true)
                    let rawTabs = tabScanner.scanTabs(in: focusedWindow, strict: false)
                    let tabs = exactTabs.isEmpty ? rawTabs : exactTabs
                    if let matchedTab = findTabSnapshot(tabs, title: tabTitle), matchedTab.isSelected {
                        return (lastFocusedTitle, true)
                    }
                }
            }

            if Date() >= deadline {
                return (lastFocusedTitle, false)
            }
            usleep(pollUS)
        }
    }

    private func availableTabsForFocusedWindow(pid: pid_t, timeoutMS: Int = 250) -> [String] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMS) / 1000.0)
        let pollUS = useconds_t(25_000)

        while true {
            if let focusedWindow = AXElement.applicationElement(pid: pid).focusedWindow() {
                let exactTabs = tabScanner.scanTabs(in: focusedWindow, strict: true)
                let rawTabs = tabScanner.scanTabs(in: focusedWindow, strict: false)
                let tabs = exactTabs.isEmpty ? rawTabs : exactTabs
                if !tabs.isEmpty || Date() >= deadline {
                    return tabs.map(\.title)
                }
            } else if Date() >= deadline {
                return []
            }

            usleep(pollUS)
        }
    }

    private func focusedTabState(pid: pid_t, targetTabTitle: String) -> AXFocusedTabState {
        guard let focusedWindow = AXElement.applicationElement(pid: pid).focusedWindow() else {
            return AXFocusedTabState(titles: [], selectedIndex: nil, targetIndex: nil)
        }
        let exactTabs = tabScanner.scanTabs(in: focusedWindow, strict: true)
        let rawTabs = tabScanner.scanTabs(in: focusedWindow, strict: false)
        let tabs = exactTabs.isEmpty ? rawTabs : exactTabs
        return AXFocusedTabState(
            titles: tabs.map(\.title),
            selectedIndex: tabs.first(where: { $0.isSelected })?.index,
            targetIndex: findTabSnapshot(tabs, title: targetTabTitle)?.index
        )
    }

    private func dedupeTitles(_ titles: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in titles {
            let title = sanitize(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }
            let key = title.lowercased()
            if seen.insert(key).inserted {
                result.append(title)
            }
        }
        return result
    }

    private func latestPersistedWindow(windowID: String) -> NotionPersistedWindowSnapshot? {
        guard let snapshot = try? persistedStateScanner.loadSnapshot() else { return nil }
        return snapshot.windows.first(where: { $0.windowID == windowID })
    }

    private func rectMatches(_ lhs: CGRect, _ rhs: CGRect?) -> Bool {
        guard let rhs else { return false }
        let tolerance: CGFloat = 24
        return abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func isLikelyOffscreenBounds(_ rect: CGRect?) -> Bool {
        guard let rect else { return false }
        if rect.minX < 0 || rect.minY < 0 {
            return true
        }
        return !NSScreen.screens.contains { screen in
            screen.frame.intersects(rect)
        }
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }

    private func duplicateWindowRecords(in records: [VerifiedWindowRecord]) -> [String] {
        var counts: [String: Int] = [:]
        for record in records {
            let key = "\(record.menuTitle)|\(record.focusedWindowTitle)|\(record.tabTitles.joined(separator: "|"))"
            counts[key, default: 0] += 1
        }
        return counts.compactMap { entry in
            entry.value > 1 ? entry.key : nil
        }
    }

    private func titleMatches(_ focusedTitle: String, _ candidateTitle: String) -> Bool {
        let lhs = focusedTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = candidateTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lhs.isEmpty || rhs.isEmpty { return false }
        return lhs == rhs
    }
}

let command = CommandParser.parse(arguments: CommandLine.arguments)
exit(Runner().run(command: command))
