// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkScanKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NetworkScanKit", targets: ["NetworkScanKit"]),
    ],
    targets: [
        .target(name: "NetworkScanKit"),
    ]
)
