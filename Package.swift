// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuestLog",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "quest", targets: ["quest"]),
        .executable(name: "QuestLog", targets: ["QuestLog"]),
    ],
    targets: [
        // Data model, storage in ~/.questlog and every change to it. Shared by the app and the CLI.
        .target(name: "QuestCore"),
        .executableTarget(name: "quest", dependencies: ["QuestCore"]),
        .executableTarget(name: "QuestLog", dependencies: ["QuestCore"]),
        .testTarget(name: "QuestCoreTests", dependencies: ["QuestCore"]),
    ],
    swiftLanguageModes: [.v5]
)
