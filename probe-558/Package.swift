// swift-tools-version: 6.0
// Throwaway real-model probe for #558; not shipped. Calls the shipped SystemModemLightExtractor.
import PackageDescription
let package = Package(
  name: "Probe558",
  platforms: [.macOS("15.0")],
  dependencies: [.package(path: "/Users/blake/Projects/NetMonitor-2.0-558/Packages/NetMonitorCore")],
  targets: [.executableTarget(
    name: "Probe",
    dependencies: [.product(name: "NetMonitorCore", package: "NetMonitorCore")],
    path: "Sources/Probe",
    swiftSettings: [.swiftLanguageMode(.v5)]
  )]
)
