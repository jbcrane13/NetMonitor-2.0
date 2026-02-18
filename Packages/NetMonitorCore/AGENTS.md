<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitorCore

## Purpose
Shared Swift package providing models, service protocols, and platform-agnostic service implementations used by both the macOS and iOS app targets. This is the primary integration point between the two platforms.

## Key Files

| File | Description |
|------|-------------|
| `Package.swift` | SPM manifest; declares dependency on `NetworkScanKit` |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Sources/NetMonitorCore/` | All source files (see `Sources/NetMonitorCore/AGENTS.md`) |

## For AI Agents

### Build
```bash
cd Packages/NetMonitorCore
swift build -c debug
swift test
```

### Modifying This Package
Changes here affect both app targets. After modifying:
1. Build the package to verify: `swift build`
2. Update platform implementations if protocols changed
3. Verify both `NetMonitor-macOS` and `NetMonitor-iOS` still build

<!-- MANUAL: -->
