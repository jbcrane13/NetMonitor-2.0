<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-02-15 -->

# NetworkScanKit Core

## Purpose

Core implementation of the composable network scan engine. Provides the fundamental types for orchestrating scan phases, accumulating results, tracking RTT metrics, managing connection budgets, and handling thermal throttling.

## Key Files

| File | Purpose |
|------|---------|
| `ScanPhase.swift` | Protocol defining composable scan phases (execute, progress, weight) |
| `ScanEngine.swift` | Actor orchestrating phases via ScanPipeline with progress tracking |
| `ScanPipeline.swift` | Defines phase ordering and concurrency (sequential vs concurrent steps) |
| `ScanContext.swift` | Sendable scan configuration (subnet, hosts, local IP, cancellation) |
| `ScanAccumulator.swift` | Actor collecting discovered devices with deduplication; tracks which devices this scan confirmed and the ARP expiry baseline |
| `DiscoveredDevice.swift` | Sendable model representing a discovered device (IP, hostname, MAC, latency, `isCached`) |
| `RTTTracker.swift` | Actor tracking RTT stats for adaptive timeout calculation |
| `ConnectionBudget.swift` | Actor managing concurrent connection limits with thermal throttling |
| `ResumeState.swift` | Actor managing scan resume state for interruption recovery |
| `ThermalThrottleMonitor.swift` | ProcessInfo-based thermal state monitoring for concurrency adaptation |
| `ARPCacheScanner.swift` | UDP probes to fill the ARP table; reads it via `sysctl` (returns nothing to sandboxed apps on macOS 27, #401); settle polling; `refreshedIPs` for presence |
| `SSDPSocketSearch.swift` | SSDP M-SEARCH over a BSD UDP socket, bound to the scan interface |
| `UPnPDeviceDescription.swift` | Parses a UPnP description's root device (friendly name, maker, model); reusable for the router IGD (#400) |
| `UPnPPortMappings.swift` | Router UPnP port forwards, read-only (#400): WAN service discovery, `GetGenericPortMappingEntry` SOAP, read loop that reports whether the list is complete |
| `UPnPDescriptionFetcher.swift` | HTTP/1.0 GET of a LAN description document, and the SOAP POST for #400, over `NWConnection` (2 s, 64 KB) |
| `DeviceNameResolver.swift` | DNS reverse lookup utility for hostname resolution |
| `IPv4Helpers.swift` | String extension for natural IPv4 sorting (192.168.1.10 before 192.168.1.100) |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Phases/` | Concrete scan phase implementations (ARP, Bonjour, TCP, SSDP, ICMP, ARP re-check, DNS) |

## For AI Agents

### Architecture Patterns

1. **All types are Sendable:** Use `actor` for mutable shared state, `struct`/`enum` for data, `@Sendable` for closures.
2. **Actor Isolation:** `ScanEngine`, `ScanAccumulator`, `RTTTracker`, `ConnectionBudget`, `ResumeState` are actors. Access requires `await`.
3. **ScanPhase Protocol:** Each phase is independent, reports progress via callback, and merges results into `ScanAccumulator`.
4. **RTT-Based Adaptive Timeouts:** `RTTTracker` maintains P50/P90 stats. Phases query it to calculate dynamic timeouts.
5. **Thermal Throttling:** `ConnectionBudget` reduces concurrency when `ProcessInfo.thermalState` is elevated.
6. **Cancellation:** `ScanContext.isCancelled` is checked by phases to support early termination.
7. **Cached devices (#378):** `ScanAccumulator.upsert(_:confirmsPresence:)` records whether the device answered this scan. Devices with no answer (only an ARP entry that did not refresh) come out of snapshots with `isCached == true`. See `Phases/AGENTS.md`.

### Working Instructions

- **Adding a New Phase:** Create a type conforming to `ScanPhase` in `Phases/`, implement `execute()`, call `accumulator.upsert(_:confirmsPresence:)` for each device (`false` unless the device answered).
- **Modifying RTT Logic:** Update `RTTTracker.swift`. Ensure stats are calculated per-subnet for accuracy.
- **Connection Budget:** Wrap connection work in `withConnectionSlot { ... }`; it acquires and releases the slot for you, including on cancellation. `ConnectionBudget`'s own acquire/release pair is internal and not called directly outside `ConnectionBudget.swift`.
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
