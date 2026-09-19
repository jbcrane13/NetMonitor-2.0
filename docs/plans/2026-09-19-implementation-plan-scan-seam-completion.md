# Implementation plan: completing the scan seam (card 6 remainder + helpful excluded work)

Source: architecture review report `~/.claude/workflow-artifacts/reports/netmonitor-2.0-architecture-review-2026-09-18.html` and the delivered epic #273 (cards 1–7, merged 2026-09-18). This plan finishes the parts of card 6 that were scoped out, plus the excluded items that card 6's completion makes load-bearing. Card 8 protocol collapse stays excluded.

Predecessor plan: `docs/plans/2026-09-18-implementation-plan-arch-deepening.md`.

## Requirements and exclusions

**Outcome.** macOS discovery becomes a real adapter over `ScanEngine`: its own work is contributed as `ScanPhase`s instead of running as post-scan `@MainActor` methods, the duplicated bounded-concurrency loops collapse into one helper, and latency precedence moves inside the accumulator. `ScanPhase` becomes a genuinely cross-platform seam.

**Request.** "Plan the remainder of card 6 — macOS post-scan work as real `ScanPhase`s, collapsing the four window loops and making that seam genuinely cross-platform — as well as any other excluded work that would help."

**In scope.**
- P1 Package foundation: bounded-concurrency helper, ranked latency in `ScanAccumulator` (ADR-014 placement), `DiscoveredDevice.openPorts`, a structured extension point on `ScanPipeline.standard`, per-phase timeout.
- P2 macOS enrichment phases + coordinator reduction + construction-site sweep (closes #291).
- P3 Corrections: the ICMP-entitlement claim (wrong, measured), and the two conformance claims card 8 identified.
- P4 (optional) #287: gate the non-deterministic node tests behind an env flag.
- P5 (optional, separate cost) Companion heartbeat/reconnect session module (card 2's "adjacent, not carded").

**Excluded.**
- Card 8 protocol collapse. Once shell name resolution and the macOS port probe are `ScanPhase`s, `ScanPhase` *is* the seam for that variation; moving `PingServiceProtocol` / `DeviceNameResolverProtocol` / `PortScannerServiceProtocol` as well would draw a second seam for the same variation, and ADR-008 endorses the current injection style.
- `DeviceTypeInferenceService` input-type change. Measured: inference reads five `LocalDevice`-only fields (`deviceType`, `isGateway`, `resolvedHostname`, `customName`, `discoveredServices`); the accumulator carries none of them and `discoveredServices` is not tracked at all. `inferDeviceTypes` is synchronous and is not one of the four window loops, so leaving it post-persistence costs nothing this plan is trying to buy.
- Any change to persisted SwiftData schema. `DiscoveredDevice.openPorts` is a transient scan model, not a persisted one.
- Pre-existing lint/format failures outside owned files (#264).
- iOS behaviour. iOS performs no vendor lookup, type inference or port scanning today; no new phase enters `ScanPipeline.standard`'s defaults.

## Repository evidence and decisions

Evidence gathered 2026-09-19 against `main` @ cf90732:

- **ICMP works in the sandboxed macOS app.** Probe run inside the app process on mini-pro-2: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` returned fd=6, errno=0, and `ICMPLatencyPhase` measured the gateway at **3.96 ms**. `ICMPLatencyPhase` uses an *unprivileged* `SOCK_DGRAM` ICMP socket, not the raw `ICMPSocket` that needs an entitlement. ADR-macOS-003 names real ICMP as primary and `ProcessPingService` (shell ping) as *fallback*, so running the phase honours the ADR rather than contradicting it. The contrary claim in `DeviceDiscoveryCoordinator.swift:251`, `lessons-learned.md:13` and the predecessor plan's D14 is wrong and is corrected in P3.
- **No shared bounded-concurrency helper exists.** `withTaskGroup` sliding windows are hand-rolled in `TCPProbeScanPhase` (4), `BonjourScanPhase` (1), `ReverseDNSScanPhase` (1) and `DeviceDiscoveryCoordinator` (4, at `:259 :300 :334 :374`). Without one helper, writing four macOS phases moves the loops rather than deleting them.
- **`DiscoveredDevice` is not on the companion wire.** It appears in NSK, and on iOS only in `DashboardViewModel`, `NetworkMapViewModel` and their views. `CompanionMessage` does not carry it. An additional optional field is safe.
- **`ScanEngine` uses one `phaseTimeout: Duration = .seconds(30)` for every phase** (`ScanEngine.swift:35`). A 15-port scan or vendor lookup over 40 devices can exceed it and be cancelled mid-flight.
- **The macOS `DeviceNameResolver` is a shell actor** (`host`, `dig`, NetBIOS) and shares its name with NSK's `public final class DeviceNameResolver` (`getnameinfo`). The macOS actor shadows the package class inside the coordinator. iOS's `DeviceDetailViewModel` binds the NSK one, so a rename of the macOS actor does not touch iOS.
- **12 construction sites** pass `arpScanner:` by name (`NetMonitorApp.swift:179,212`, `MenuBarPopoverView.swift:580`, 9 test files). One sweep.
- **All four post-scan steps read and write persisted `LocalDevice` rows**, not accumulator entries. This is the structural reason they are not phases today, and the source of the two product-visible changes below.

### Decisions (product-visible or interface-shaping)

| ID | Decision | Rationale / consequence |
|----|----------|-------------------------|
| **E1** | **Enrichment applies to this scan's devices only.** Today `resolveDeviceNames` enriches every profile row with an empty hostname and `measureDeviceLatencies` pings every `.online` row — including rows from earlier scans not seen this time, because `markOfflineDevices` runs last. Phase-based enrichment sees only the accumulator. | Product-visible: stale devices stop being re-resolved and re-pinged. Argued correct (they are about to be marked offline) and it removes work from every scan. A "seen last scan, absent this scan" device goes in the golden fixture. |
| **E2** | **Progressive display is preserved with two idempotent merges.** Mechanism: the coordinator holds a once-flag, set the first time the progress callback reports a `phaseID` in the enrichment set, which triggers `await MainActor.run { mergeDiscoveredDevices(snapshot, profileID:) }`; the pipeline then completes and a second merge plus `markOfflineDevices` runs. The three enrichment phases carry `weight` values that place that transition near today's 0.8. | Without this, first appearance moves from ~0.8 to ~1.0 and the user stares at an empty list through the enrichment tail. `mergeDiscoveredDevices` is already upsert-by-MAC-then-IP, so calling it twice is safe; a test asserts two merges produce the same rows as one. |
| **E3** | **macOS scan latency comes from `ICMPLatencyPhase`, with shell ping retained as a fallback phase, not as an unconditional pass.** `measureDeviceLatencies`'s unconditional 3-ping-per-device loop is deleted; a `ShellPingLatencyPhase` in `trailingSteps` pings only entries whose latency source is below `.icmp`. | Measured above. ADR-macOS-003 names `ProcessPingService` as the *fallback*, so removing it entirely would let a future ICMP failure degrade silently to TCP-handshake latency — the ~70 ms inflation ADR-014 exists to prevent. When ICMP covers every device the phase sends zero pings, so the speedup still lands; it is also the only writer of E4's `.shellPing` rank. Product-visible: displayed latency becomes a **single** ICMP probe rather than a 3-ping shell average (`ICMPLatencyPhase` sends one echo request per host), so values will be noisier. If that reads badly on the node, add a probe-count parameter to the phase rather than reinstating the shell pass. |
| **E4** | **`ScanAccumulator` owns latency precedence.** One `setLatency(ip:value:source:)` with ranked `LatencySource` (`tcpHandshake` < `icmp` < `shellPing`); a lower-ranked source never overwrites a higher-ranked value. `updateLatency` / `replaceLatency` are deleted and their callers updated in the same PR. | This is card 7's placement note, excluded last time as cosmetic. With TCP probe and ICMP both writing in one run it becomes a phase-ordering hazard, so it is now required. Implements ADR-014 inside the module instead of by caller convention. |
| **E5** | **`ScanPipeline.standard` gains `latencyPhase:` and `trailingSteps:`, both defaulted.** macOS supplies trailing steps; it never rebuilds `ScanPipeline(steps:)` by hand. | Rebuilding the pipeline inline is exactly the drift that caused ADR-014's bug and that card 7 removed. Defaults keep iOS byte-identical. |
| **E6** | **`ScanPhase` gains `var timeout: Duration? { get }`, defaulted `nil`** (engine falls back to its own `phaseTimeout`). | Enrichment phases legitimately run longer than discovery phases; without this the engine silently cancels them at 30 s. |
| **E7** | **`DiscoveredDevice` gains `openPorts: [Int]?`**, additive and optional. | Lets the port-scan phase carry results to persistence. Not on the wire; iOS ignores it. |
| **E8** | **The macOS `DeviceNameResolver` actor is renamed `ShellDeviceNameResolver`.** | Removes name shadowing of the NSK class that is currently "doing the job a seam should" (report, card 8). Mechanical; iOS unaffected. |

## Architecture and interfaces

### P1 — package foundation (NetworkScanKit + NetMonitorCore)

`forEachBounded(_ items:limit:operation:)` — a `Sendable` free function in NSK that runs an async operation over a sequence with a fixed concurrency window and returns results as they complete, replacing the hand-rolled `withTaskGroup` + iterator + `activeCount` shape. `TCPProbeScanPhase` (4 sites), `BonjourScanPhase` (1), `ReverseDNSScanPhase` (1) adopt it; each keeps its existing window size so behaviour is unchanged.

`ScanAccumulator`: `public enum LatencySource: Int, Comparable, Sendable { case tcpHandshake, icmp, shellPing }` and `setLatency(ip:value:source:)`; `updateLatency`/`replaceLatency` deleted, `TCPProbeScanPhase` and `ICMPLatencyPhase` updated to pass their source.

`DiscoveredDevice`: `public let openPorts: [Int]?` with a default in the full init (E7).

`ScanPipeline.standard(bonjourServiceProvider:bonjourStopProvider:latencyPhase:trailingSteps:)` (E5). `ScanPhase.timeout` with a protocol extension default of `nil`; `ScanEngine` uses `phase.timeout ?? phaseTimeout` (E6).

Verified entirely with `swift test` in both packages — no app build required.

### P2 — macOS enrichment phases and coordinator reduction

Three macOS-target phases, each taking its dependency by injection so the fixture pipeline stays deterministic:

- `ShellNameResolutionPhase(resolver: ShellDeviceNameResolver)` — resolves accumulator entries that still have no hostname, in `trailingSteps`. It does **not** replace `ReverseDNSScanPhase`: today the engine already runs reverse DNS (`getnameinfo`) and the coordinator's shell resolver then handles the leftovers, so "reverse DNS first, shell for what it missed" is current behaviour and is preserved exactly.
- `VendorLookupPhase(service: MACVendorLookupService)` — fills `vendor` for entries with a MAC and no vendor.
- `QuickPortScanPhase(checker:)` — the existing 15-port check, writing `openPorts` (E7); the checker runs under `withConnectionSlot` as it does today.

**Widening the persistence path.** Enrichment written to the accumulator currently has no route to SwiftData: `mapDiscoveredDevices` produces `LocalDiscoveredDevice` (`MacNetworkMonitor.swift:62`), which carries only `ipAddress`, `macAddress`, `hostname`. It gains `vendor`, `openPorts` and `latency`; `mapDiscoveredDevices` fills them from `DiscoveredDevice`; and `mergeDiscoveredDevices` writes each **only when non-nil**, so E2's first (sparse) merge cannot clear values that the second merge would supply. This changes the S6 golden fixture's types, which is expected — both files are owned by this slice.

`DeviceDiscoveryCoordinator.startScan()` becomes: build context → `pipelineFactory` returns `ScanPipeline.standard(..., trailingSteps: [Step(phases: [names, vendors, ports, shellPingFallback], concurrent: true)])` → run engine → merge at the discovery→enrichment transition (E2) → final merge → `inferDeviceTypes` → `markOfflineDevices` → profile bookkeeping. `measureDeviceLatencies`, `resolveDeviceNames`, `resolveDeviceVendors` and `quickPortScan` are deleted with their four window loops (E3).

`portChecker` leaves the init (it is now the port phase's dependency); `arpScanner` leaves with #291; `ARPScannerService.swift` and `ARPScannerServiceTests.swift` are deleted if nothing else references them. All 12 construction sites are swept in this slice.

### P3 — corrections

Correct the ICMP-entitlement claim in `DeviceDiscoveryCoordinator.swift:251` (removed with E3's deletion) and `lessons-learned.md:13`; add a consequence line to ADR-macOS-003 recording that unprivileged `SOCK_DGRAM` ICMP works in the sandbox, with the measurement; and append a dated correction note to the predecessor plan's D14, which is the cited source of the false claim. Fix the two conformance claims card 8 named: `NetMonitor-macOS/Platform/AGENTS.md:14` (says `ShellPingService` conforms to `PingServiceProtocol`; it does not) and the `ServiceProtocols.swift:465` doc comment (says `CompanionService` conforms to `MacConnectionServiceProtocol`; it does not).

## Deliverable slices

| Slice | Acceptance | Owned files | Depends on | Verification |
|---|---|---|---|---|
| **P1** foundation | `forEachBounded` exists and the 6 NSK loop sites use it; `setLatency(ip:value:source:)` replaces both old methods (grep for `updateLatency\|replaceLatency` in Sources is empty); `DiscoveredDevice.openPorts` present; `standard` takes `latencyPhase`/`trailingSteps`; `ScanPhase.timeout` honoured by the engine; a test proves a lower-ranked source cannot overwrite a higher-ranked latency; NSK + Core suites pass | `ScanAccumulator.swift`, `DiscoveredDevice.swift`, `ScanPipeline.swift`, `ScanPhase.swift`, `ScanEngine.swift`, `Phases/*.swift` (loop sites only), new `Concurrency.swift`, NSK tests | — | `swift test --no-parallel` both packages |
| **P2** macOS phases | Three phases exist as macOS types; coordinator contains no `withTaskGroup` and no `measureDeviceLatencies`/`resolveDeviceNames`/`resolveDeviceVendors`/`quickPortScan`; `arpScanner` and `portChecker` gone from the init; 12 sites updated; golden-row equivalence incl. vendor/openPorts/lastLatency; two-merge test (E2); stale-device test (E1) | `DeviceDiscoveryCoordinator.swift`, new `Platform/Phases/*.swift`, `DeviceNameResolver.swift` (rename), `MacNetworkMonitor.swift` (+ its tests) for `LocalDiscoveredDevice`, the 12 construction sites, macOS coordinator tests and the S6 fixtures | P1 | node: `DeviceDiscoveryCoordinatorTests` + live scan; both app builds |
| **P3** corrections | The four false/stale claims fixed; ADR-macOS-003 amended with the measurement | `lessons-learned.md`, `docs/ADR-macOS.md`, `NetMonitor-macOS/Platform/AGENTS.md`, `ServiceProtocols.swift` (comment only) | — (parallel) | docs only |
| **P4** *(optional)* #287 | Live-Bonjour suites and the two iOS suites skip unless `NETMONITOR_LIVE_SCAN=1` (reusing the flag the S6 live-scan test already defines, rather than introducing a second one); full macOS + iOS targets green on the node without timeout flags | those test files | — (parallel) | node: both unit targets |
| **P5** *(optional, separate cost)* companion session | Heartbeat last-received time and reconnect state own a testable module; iOS `MacConnectionService` delegates to it | `MacConnectionService.swift`, new Core session type, its tests. Explicitly **not** the macOS `CompanionMessageHandler*Tests`, which construct a coordinator and belong to P2's sweep | — (parallel) | Core suite; iOS build |

## Integration order and shared-file ownership

P1 → P2 strictly sequential: P2's phases depend on P1's `trailingSteps`, `setLatency`, `openPorts` and `timeout`. This chain is one tightly coupled set, so unlike epic #273 it does **not** parallelise — two sequential workers, not four concurrent ones. P3, P4 and P5 share no files with the chain and run alongside P1.

Shared-file risk is low: P1 is package-only, P2 is macOS-target-only, P3 is docs plus one comment. The only overlap is `ServiceProtocols.swift` (P3 comment only; no slice edits its types).

## Acceptance and release tasks

- Both apps build; NSK and Core suites pass with only the two known environmental failures.
- Node: full `NetMonitor-macOSTests` and `NetMonitor-iOSTests` no worse than the #287 baseline.
- Node live scan reports at least `LIVE_SCAN devices=<n> gateway=found`, extended to `enriched_names=<n> enriched_vendors=<n> latency_source=icmp`, with epic #273's `devices=1 gateway=found` as the floor.
- `grep withTaskGroup NetMonitor-macOS/Platform/DeviceDiscoveryCoordinator.swift` is empty.
- A macOS type conforms to `ScanPhase` (the card-6 win that did not land in #279).

## Risks and unresolved decisions

- **E3 rests on one measurement.** The probe ran in an ad-hoc-signed (`CODE_SIGN_IDENTITY="-"`) test host. Ad-hoc signing does embed entitlements, but before deleting shell ping P2 must re-confirm on a Developer-ID-signed build, or keep `ICMPLatencyPhase`'s existing silent-skip and have the coordinator log when latency is absent. Cheap confirmation: `codesign -d --entitlements - <built app>` plus the same probe.
- **E1/E2 are behaviour changes** in the most-used macOS screen. They are the reason the golden-row fixture exists; if either test proves awkward to write deterministically, stop and report rather than weaken the assertion.
- **Vendor lookup is a network call inside the pipeline.** With E6 it gets its own timeout; if macvendors.com is slow the phase must degrade to "no vendor", never stall the scan.
- **P5 is genuinely optional** and adds roughly a third to the plan. It is listed because it is the one excluded item with real reliability value, not because card 6 needs it.
