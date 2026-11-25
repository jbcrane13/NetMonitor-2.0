// swift-tools-version: 5.10
// Throwaway real-model probe for #452; not shipped.
import PackageDescription
let package = Package(
  name: "Probe452",
  platforms: [.macOS("15.0")],
  dependencies: [.package(path: "/Users/blake/Projects/NetMonitor-2.0-580/Packages/NetMonitorCore")],
  targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "NetMonitorCore", package: "NetMonitorCore")], path: "Sources/Probe")]
)
