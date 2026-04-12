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
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.49.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "NetMonitorCore",
            dependencies: [
                "NetworkScanKit",
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
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
