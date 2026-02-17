// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetMonitorCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "NetMonitorCore",
            targets: ["NetMonitorCore"]
        ),
    ],
    targets: [
        .target(
            name: "NetMonitorCore",
            path: "Sources/NetMonitorCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NetMonitorCoreTests",
            dependencies: ["NetMonitorCore"],
            path: "Tests/NetMonitorCoreTests"
        ),
    ]
)
