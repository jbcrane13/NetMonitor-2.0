// swift-tools-version: 5.10
// Throwaway real-model probe for #579; not shipped.
import PackageDescription
let package = Package(
  name: "Probe579",
  platforms: [.macOS("15.0")],
  dependencies: [.package(path: "/Users/blake/Projects/NetMonitor-2.0-579/Packages/NetMonitorCore")],
  targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "NetMonitorCore", package: "NetMonitorCore")], path: "Sources/Probe")]
)
