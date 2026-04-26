// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "notion-tabs-poc",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "NotionTabsCore", targets: ["NotionTabsCore"]),
        .executable(name: "notion-tabs", targets: ["notion-tabs"]),
        .executable(name: "notion-tabs-poc", targets: ["NotionTabsPOC"]),
        .executable(name: "notion-tabs-v2", targets: ["NotionTabsV2"]),
    ],
    targets: [
        .target(
            name: "NotionTabsCore",
            path: "Sources/NotionTabsCore"
        ),
        .executableTarget(
            name: "notion-tabs",
            dependencies: ["NotionTabsCore"],
            path: "Sources/notion-tabs"
        ),
        .executableTarget(
            name: "NotionTabsPOC",
            path: "Sources/NotionTabsPOC"
        ),
        .executableTarget(
            name: "NotionTabsV2",
            path: "Sources/NotionTabsV2"
        ),
    ]
)
