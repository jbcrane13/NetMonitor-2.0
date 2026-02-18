<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# Packages

## Purpose
Swift Package Manager packages providing shared, platform-agnostic functionality. Both packages target macOS 15.0 and iOS 18.0 and use Swift 6 language mode with strict concurrency.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `NetMonitorCore/` | Shared models, service protocols, and core service implementations (see `NetMonitorCore/AGENTS.md`) |
| `NetworkScanKit/` | Multi-phase network device discovery engine (see `NetworkScanKit/AGENTS.md`) |

## For AI Agents

### Dependency Order
`NetworkScanKit` has no internal dependencies. `NetMonitorCore` depends on `NetworkScanKit`. App targets depend on `NetMonitorCore`.

### Modifying Packages
- Changes to `ServiceProtocols.swift` in NetMonitorCore affect **both** app targets — update all implementations
- Changes to `DiscoveredDevice` in NetworkScanKit ripple through NetMonitorCore and both app targets
- Run `swift build` from the package directory to verify before testing in app targets

<!-- MANUAL: -->
