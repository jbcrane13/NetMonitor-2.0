<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# NetworkScanKitTests

## Purpose
Unit tests for the NetworkScanKit Swift package. Validates the multi-phase scan pipeline, device accumulation, connection budget management, thermal throttling, IP address helpers, RTT tracking, and the `DiscoveredDevice` model. Tests exercise the engine and pipeline without performing real network I/O by using `FixturePhase` stand-ins for actual scan phases.

## Key Files
| File | Description |
|------|-------------|
| `ConnectionBudgetTests.swift` | Actor-based `ConnectionBudget`: initial count, acquire/release semantics, floor at zero, reset (clears count + unblocks waiting acquires), limit boundary enforcement |
| `DiscoveredDeviceTests.swift` | `DiscoveredDevice` init (convenience and full), `displayName` fallback chain (hostname → IP), `latencyText` formatting and source-aware labels (via Mac, UPnP, Bonjour, dash), `ipSortKey` numeric ordering, `BonjourServiceInfo` init |
| `IPv4HelpersTests.swift` | `isValidIPv4Address` (valid, wrong component count, out of range, non-numeric, leading zeros), `cleanedIPv4Address` zone-ID stripping, `extractIPFromSSDPResponse` (LOCATION header, case-insensitive, fallback, no-IP), `firstIPv4Address(in:)`, `IPv4CIDR` parsing (valid /24//16//30, error cases for bad format/IP/prefix), `IPv4Helpers.hostsInSubnet` (count, too-large subnet guard, /32 and /31 edge cases, invalid CIDR) |
| `ResumeStateTests.swift` | Actor-based `ResumeState` (NetworkScanKit copy): initial state, `setResumed`, `tryResume` first-call/subsequent-call behavior |
| `RTTTrackerTests.swift` | Actor-based `RTTTracker`: initial sample count, returns base timeout before `minSamples` reached, ignores zero/negative RTT, returns adaptive timeout after sufficient samples, clamping to `minTimeout`/`maxTimeout`, custom `minSamples` threshold |
| `ScanAccumulatorTests.swift` | Actor-based `ScanAccumulator`: starts empty, upsert adds new device, multiple unique devices, merge semantics (existing fields win, nil fields filled from incoming), `contains`, `knownIPs`, `ipsWithoutLatency`, `allDeviceIPs`, `updateLatency` (sets when nil, no-op if already set), `replaceLatency` (always overwrites), `sortedSnapshot` numeric IP order, `reset` |
| `ScanContextTests.swift` | `ScanContext` init: stores `hosts`, callable `subnetFilter`, `localIP`, `networkProfile` (nil default and stored), `scanStrategy` (defaults to `.full`, can be `.remote`), full parameter combination |
| `ScanEngineTests.swift` | `ScanEngine` integration: sequential pipeline phases report progress and return IP-sorted results, concurrent step executes all phases, zero-weight pipeline skips phase execution and returns existing accumulator snapshot, `reset` clears accumulator; uses `FixturePhase` and `ProgressRecorder` actor fixtures |
| `ScanPipelineTests.swift` | `ScanPipeline` and `ScanPipeline.Step` init, `ScanPipeline.standard()` structure (4 steps, step 0–1 concurrent with 2 phases each, step 2–3 sequential with 1 phase each), `ScanPipeline.forStrategy(.full)` matches standard, `forStrategy(.remote)` has 2 steps (tcpProbe sequential; icmpLatency + reverseDNS concurrent), strategy phase inclusion/exclusion assertions |
| `ThermalThrottleMonitorTests.swift` | `ThermalThrottleMonitor.shared`: multiplier is one of `[0.25, 0.5, 1.0]`, `effectiveLimit` is always ≥ 1 (including zero base), consistency with multiplier, does not exceed base |

## For AI Agents

### Working In This Directory
- All tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Do not add XCTest.
- Tests import `@testable import NetworkScanKit`. Internal types like `FixturePhase` and `ProgressRecorder` in `ScanEngineTests.swift` are `private` to that file — do not move them.
- `ConnectionBudget`, `ScanAccumulator`, `RTTTracker`, and `ResumeState` are actors. All access is `async`. Tests must be `async` and use `await`.
- `ScanEngineTests.swift` tests real `ScanEngine` + `ScanPipeline` behavior using stub `FixturePhase` implementations. When adding engine tests, implement `ScanPhase` in a local `private struct` rather than creating real network phases.
- `ThermalThrottleMonitor.shared` reads the system thermal state, so `multiplier` is non-deterministic in tests. Tests assert only that the value is within the valid set and that `effectiveLimit` is ≥ 1.
- `ResumeStateTests.swift` here is a parallel of the same-named file in `NetMonitorCoreTests` — `NetworkScanKit` has its own copy of `ResumeState`.
- `ScanContextTests.swift` uses `NetworkScanProfile` (the `NetworkScanKit`-scoped type, renamed from `NetworkProfile` to resolve ambiguity with `NetMonitorCore.NetworkProfile`).

### Testing Requirements
```bash
# From the package directory
swift test

# Or via xcodebuild
xcodebuild test -scheme NetworkScanKit -destination 'platform=macOS'
```

Tests run on macOS only (no iOS simulator target for this package).

### Common Patterns
- **Actor state tests**: call `await actor.method()` then assert `await actor.property`. Keep tests `async`.
- **Fixture phases**: implement `ScanPhase` with a local `private struct FixturePhase` that calls `onProgress` with preset values and upserts preset IPs into the accumulator. See `ScanEngineTests.swift` for the canonical example.
- **Pipeline structure tests**: use `pipeline.steps[n].phases.count` and `pipeline.steps[n].concurrent` to assert structural properties without executing real network I/O.
- **IP sort key**: `String.ipSortKey` is tested via `DiscoveredDeviceTests.swift`. The key is `192 * 16_777_216 + 168 * 65_536 + octet3 * 256 + octet4`.
- **CIDR error cases**: `IPv4CIDR(parsing:)` throws typed `CIDRParseError` cases — use `#expect(throws: CIDRParseError.xxx)` to assert specific error types.

## Dependencies

### Internal
- `NetworkScanKit` (package under test) — all public and `@testable` types including `ScanEngine`, `ScanPipeline`, `ScanPhase`, `ScanContext`, `ScanAccumulator`, `ConnectionBudget`, `RTTTracker`, `ThermalThrottleMonitor`, `ResumeState`, `DiscoveredDevice`, `IPv4Helpers`, `IPv4CIDR`, `NetworkScanProfile`
- `Foundation` — `Date`, `UUID`

<!-- MANUAL: -->
