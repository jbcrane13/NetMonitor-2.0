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
    dependencies: [
        .package(path: "../NetworkScanKit"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.49.0")
    ],
    targets: [
        .target(
            name: "NetMonitorCore",
            dependencies: [
                "NetworkScanKit",
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Sources/NetMonitorCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NetMonitorCoreTests",
            dependencies: ["NetMonitorCore"],
            path: "Tests/NetMonitorCoreTests",
            resources: [.process("TestFixtures")]
        ),
    ]
)
