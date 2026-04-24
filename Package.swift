// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "notion-tabs-poc",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "notion-tabs-poc", targets: ["NotionTabsPOC"]),
    ],
    targets: [
        .executableTarget(
            name: "NotionTabsPOC",
            path: "Sources/NotionTabsPOC"
        ),
    ]
)
