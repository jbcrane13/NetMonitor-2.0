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
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.10.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0")
    ],
    targets: [
        // Reads the resolver's DNS servers via res_ninit, which Swift can't import directly (#397).
        .target(
            name: "CResolv",
            path: "Sources/CResolv",
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        .target(
            name: "NetMonitorCore",
            dependencies: [
                "CResolv",
                "NetworkScanKit",
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/NetMonitorCore",
            resources: [.copy("Resources/oui.tsv")],
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
