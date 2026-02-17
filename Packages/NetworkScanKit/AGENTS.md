# NetworkScanKit

**Parent:** [../AGENTS.md](../AGENTS.md)
**Generated:** 2026-02-15

## Purpose

NetworkScanKit is a standalone Swift Package Manager (SPM) library providing composable, high-performance network scanning capabilities. It uses a phase-based architecture where each scan technique (ARP, Bonjour, TCP probe, SSDP, Reverse DNS) is isolated and can be orchestrated sequentially or concurrently.

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | SPM manifest defining the NetworkScanKit library target |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Sources/NetworkScanKit/` | Core scan engine, phases, and utilities |

## For AI Agents

### Working with NetworkScanKit

1. **Package Structure:** This is an SPM package. Any changes require running tests via the parent Xcode project.
2. **Strict Concurrency:** All types are Sendable. Use `actor` for mutable shared state, `@Sendable` closures for callbacks.
3. **Phase Protocol:** New scan techniques should conform to `ScanPhase` protocol with `id`, `displayName`, `weight`, and `execute()`.
4. **Testing:** Run package tests from the parent project: `xcodebuild test -scheme Netmonitor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
5. **Import Path:** Consumers import via `import NetworkScanKit`.

### Dependencies

- Foundation (system)
- Network.framework (for TCP connections)
- No external dependencies

### Integration

- Used by `DeviceDiscoveryService` in the main app
- Designed for iOS 18+ and macOS 15+
- Swift 6 with complete strict concurrency checking
