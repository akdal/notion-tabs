import Foundation
import NotionTabsCore

enum Command {
    case list(json: Bool)
    case focusWindow(window: String, json: Bool)
    case focusTab(window: String, tab: String, json: Bool)
    case help(json: Bool)

    var json: Bool {
        switch self {
        case let .list(json),
             let .focusWindow(_, json),
             let .focusTab(_, _, json),
             let .help(json):
            return json
        }
    }
}

func parse(_ args: [String]) -> Command {
    let json = hasFlag(args, "--json")
    guard args.count >= 2 else { return .help(json: json) }
    switch args[1] {
    case "list":
        return .list(json: json)
    case "focus-window":
        guard let window = value(args, "--window") ?? value(args, "--window-id") else { return .help(json: json) }
        if let tab = value(args, "--tab") ?? value(args, "--tab-id") ?? value(args, "--tab-title") {
            return .focusTab(window: window, tab: tab, json: json)
        }
        return .focusWindow(window: window, json: json)
    case "focus-tab":
        guard
            let window = value(args, "--window") ?? value(args, "--window-id"),
            let tab = value(args, "--tab") ?? value(args, "--tab-id") ?? value(args, "--tab-title")
        else {
            return .help(json: json)
        }
        return .focusTab(window: window, tab: tab, json: json)
    case "--help", "-h", "help":
        return .help(json: json)
    default:
        return .help(json: json)
    }
}

func value(_ args: [String], _ flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return nil
    }
    return args[index + 1]
}

func hasFlag(_ args: [String], _ flag: String) -> Bool {
    args.contains(flag)
}

func printHelp() {
    print(
        """
        notion-tabs

        Commands:
          notion-tabs list [--json]
          notion-tabs focus-window --window <index|id-prefix> [--json]
          notion-tabs focus-tab --window <index|id-prefix> --tab <index|id-prefix|exact-title> [--json]

        Examples:
          notion-tabs list
          notion-tabs list --json
          notion-tabs focus-window --window 3
          notion-tabs focus-tab --window 3 --tab 1
          notion-tabs focus-window --window 3 --tab 1
          notion-tabs focus-tab --window 2 --tab "Docs 작성/제작" --json
        """
    )
}

func render(_ snapshot: ListSnapshot) {
    print("focused: \(snapshot.focusedTitle ?? "<none>")")
    if let modifiedAt = snapshot.stateModifiedAt {
        print("state: \(snapshot.statePath) modified=\(ISO8601DateFormatter().string(from: modifiedAt))")
    } else {
        print("state: \(snapshot.statePath)")
    }
    print("hint: use --window <number> and --tab <number> from this list")
    print("legend: > focused now by AX, * persisted active from state.json")
    for window in snapshot.windows {
        let windowMark = window.tabs.contains(where: \.isAXFocused) ? "*" : " "
        print("\(windowMark) [\(window.index)] \(window.persistedActiveTitle) id=\(short(window.id)) tabs=\(window.tabs.count)")
        for tab in window.tabs {
            let mark = tab.isAXFocused ? ">" : (tab.isPersistedActive ? "*" : " ")
            print("    \(mark) [\(tab.index)] \(tab.title) id=\(short(tab.id))")
        }
    }
}

func short(_ id: String) -> String {
    String(id.prefix(8))
}

func printJSON(_ payload: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        print("{\"success\":false,\"error\":{\"code\":\"JSON_SERIALIZATION_FAILED\",\"message\":\"Failed to render JSON.\"}}")
        return
    }
    print(text)
}

func isoString(_ date: Date?) -> String? {
    guard let date else { return nil }
    return ISO8601DateFormatter().string(from: date)
}

func listJSON(_ snapshot: ListSnapshot) -> [String: Any] {
    [
        "success": true,
        "focusedTitle": snapshot.focusedTitle as Any,
        "state": [
            "path": snapshot.statePath,
            "modifiedAt": isoString(snapshot.stateModifiedAt) as Any,
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

func focusJSON(_ result: FocusResult) -> [String: Any] {
    [
        "success": result.success,
        "targetTitle": result.targetTitle,
        "focusedTitle": result.focusedTitle as Any,
        "strategy": result.strategy as Any,
        "message": result.message,
    ]
}

func errorJSON(_ error: Error) -> [String: Any] {
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

let service = NotionTabsService()
let parsed = parse(CommandLine.arguments)

do {
    switch parsed {
    case let .list(json):
        let snapshot = try service.listWindows()
        if json {
            printJSON(listJSON(snapshot))
        } else {
            render(snapshot)
        }
    case let .focusWindow(window, json):
        let result = try service.focusWindow(WindowRef(window))
        if json {
            printJSON(focusJSON(result))
        } else {
            print(result.message)
        }
        if !result.success { exit(1) }
    case let .focusTab(window, tab, json):
        let result = try service.focusTab(window: WindowRef(window), tab: TabRef(tab))
        if json {
            printJSON(focusJSON(result))
        } else {
            print(result.message)
        }
        if !result.success { exit(1) }
    case let .help(json):
        if json {
            printJSON([
                "success": true,
                "usage": "notion-tabs list|focus-window|focus-tab [--json]",
            ])
        } else {
            printHelp()
        }
    }
} catch {
    if parsed.json {
        printJSON(errorJSON(error))
    } else if let localized = error as? LocalizedError, let description = localized.errorDescription {
        fputs("error: \(description)\n", stderr)
    } else {
        fputs("error: \(error)\n", stderr)
    }
    exit(1)
}
