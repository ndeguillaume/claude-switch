// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeSwitch",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeSwitchCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ClaudeSwitch",
            dependencies: ["ClaudeSwitchCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ClaudeSwitchCoreTests", dependencies: ["ClaudeSwitchCore"]),
    ]
)
