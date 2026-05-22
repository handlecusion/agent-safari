// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agent-safari",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agent-safari", targets: ["AgentSafari"]),
    ],
    targets: [
        .target(
            name: "AgentSafariCore",
            path: "Sources/AgentSafariCore"
        ),
        .executableTarget(
            name: "AgentSafari",
            dependencies: ["AgentSafariCore"],
            path: "Sources/AgentSafari"
        ),
        .testTarget(
            name: "AgentSafariCoreTests",
            dependencies: ["AgentSafariCore"],
            path: "Tests/AgentSafariCoreTests"
        )
    ]
)
