# NetworkScanKit Core

**Parent:** [../../AGENTS.md](../../AGENTS.md)
**Generated:** 2026-02-15

## Purpose

Core implementation of the composable network scan engine. Provides the fundamental types for orchestrating scan phases, accumulating results, tracking RTT metrics, managing connection budgets, and handling thermal throttling.

## Key Files

| File | Purpose |
|------|---------|
| `ScanPhase.swift` | Protocol defining composable scan phases (execute, progress, weight) |
| `ScanEngine.swift` | Actor orchestrating phases via ScanPipeline with progress tracking |
| `ScanPipeline.swift` | Defines phase ordering and concurrency (sequential vs concurrent steps) |
| `ScanContext.swift` | Sendable scan configuration (subnet, hosts, local IP, cancellation) |
| `ScanAccumulator.swift` | Actor collecting discovered devices with deduplication |
| `DiscoveredDevice.swift` | Sendable model representing a discovered device (IP, hostname, MAC, latency) |
| `RTTTracker.swift` | Actor tracking RTT stats for adaptive timeout calculation |
| `ConnectionBudget.swift` | Actor managing concurrent connection limits with thermal throttling |
| `ResumeState.swift` | Actor managing scan resume state for interruption recovery |
| `ThermalThrottleMonitor.swift` | ProcessInfo-based thermal state monitoring for concurrency adaptation |
| `ARPCacheScanner.swift` | ARP cache parsing utility (`/usr/sbin/arp -an`) |
| `DeviceNameResolver.swift` | DNS reverse lookup utility for hostname resolution |
| `IPv4Helpers.swift` | String extension for natural IPv4 sorting (192.168.1.10 before 192.168.1.100) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Phases/` | Concrete scan phase implementations (ARP, Bonjour, TCP, SSDP, DNS) |

## For AI Agents

### Architecture Patterns

1. **All types are Sendable:** Use `actor` for mutable shared state, `struct`/`enum` for data, `@Sendable` for closures.
2. **Actor Isolation:** `ScanEngine`, `ScanAccumulator`, `RTTTracker`, `ConnectionBudget`, `ResumeState` are actors. Access requires `await`.
3. **ScanPhase Protocol:** Each phase is independent, reports progress via callback, and merges results into `ScanAccumulator`.
4. **RTT-Based Adaptive Timeouts:** `RTTTracker` maintains P50/P90 stats. Phases query it to calculate dynamic timeouts.
5. **Thermal Throttling:** `ConnectionBudget` reduces concurrency when `ProcessInfo.thermalState` is elevated.
6. **Cancellation:** `ScanContext.isCancelled` is checked by phases to support early termination.

### Working Instructions

- **Adding a New Phase:** Create a type conforming to `ScanPhase` in `Phases/`, implement `execute()`, call `accumulator.merge()` for each device.
- **Modifying RTT Logic:** Update `RTTTracker.swift`. Ensure stats are calculated per-subnet for accuracy.
- **Connection Budget:** `ConnectionBudget.acquire()` / `release()` must be balanced. Use `defer` or `withThrowingTaskGroup`.
- **Resume State:** `ResumeState` allows pausing/resuming scans by tracking completed IPs. Update on each successful probe.

### Testing

Run unit tests from parent project:
```bash
xcodebuild test -scheme Netmonitor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Dependencies

- Foundation (DateFormatter, ProcessInfo, URLSession for DNS)
- Network.framework (NWConnection for TCP probes)
- No third-party dependencies
