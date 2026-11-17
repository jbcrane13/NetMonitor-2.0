<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-15 -->

# NetworkScanKit Phases

## Purpose

Concrete implementations of network discovery techniques. Each phase conforms to `ScanPhase` and performs a specific discovery method (ARP probing and table reads, Bonjour/mDNS discovery, TCP probing, SSDP multicast, ICMP latency, the ARP re-check, reverse DNS lookups).

## Key Files

| File | Purpose |
|------|---------|
| `ARPScanPhase.swift` | Sends UDP probes to fill the ARP table, then reads it (via `ARPCacheScanner`) until it settles |
| `BonjourScanPhase.swift` | Discovers mDNS/Bonjour services with adaptive exit timeout |
| `TCPProbeScanPhase.swift` | TCP connect probes to common ports with RTT-adaptive timeouts |
| `SSDPScanPhase.swift` | SSDP (UPnP) M-SEARCH discovery plus device descriptions (name, maker, model) |
| `ICMPLatencyPhase.swift` | ICMP echo sweep that fills in latency for discovered devices |
| `ARPRecheckPhase.swift` | Re-reads the ARP table after ICMP and confirms devices whose entry was refreshed |
| `ReverseDNSScanPhase.swift` | DNS PTR lookups to resolve hostnames for discovered IPs |

## For AI Agents

### Phase-Specific Patterns

**ARPScanPhase:**
- Reads the ARP table first and records each entry's expiry as a baseline (`accumulator.recordARPBaseline`).
- Sends fire-and-forget UDP probes to every host (`ARPCacheScanner.populateARPCache`) so the kernel resolves them.
- Reads the table with `ARPCacheScanner.readARPEntries()`: a routing-table `sysctl` (`NET_RT_FLAGS`, `RTF_LLINFO`). On macOS, when the sysctl returns no entries (seen on macOS 27.2, #401), it falls back to parsing `/usr/sbin/arp -anl`. iOS uses the sysctl only.
- Settle polling (#379): `ARPCacheScanner.pollUntilSettled` re-reads every 250 ms and stops after 500 ms with no new IP, capped at 2 s.
- An entry confirms presence only if it is new since the baseline or its expiry moved forward (`refreshedIPs`). Other entries are upserted with `confirmsPresence: false`, so the device stays cached unless a later phase answers for it.
- Weight: 0.10.

**ARPRecheckPhase:**
- Runs after the latency step. Pings make the kernel re-check entries even for hosts that drop ICMP, so their expiry moves forward.
- Compares unconfirmed devices' entries with the ARP baseline and calls `accumulator.confirmPresence` for refreshed ones.
- Weight: 0.01.

**BonjourScanPhase:**
- Uses `NetService` and `NetServiceBrowser` for mDNS discovery.
- Adaptive exit timeout: waits until no new services found for N seconds.
- Supports custom service type filtering (default: `_services._dns-sd._udp`).
- Weight: 0.13.

**TCPProbeScanPhase:**
- Probes common ports (22, 80, 443, 445, etc.) via `NWConnection`.
- Queries `RTTTracker` for adaptive timeout calculation (P90 + buffer).
- Respects `ConnectionBudget` for thermal throttling.
- Highest weight: 0.55 (most time-consuming).
- Uses `withThrowingTaskGroup` for concurrent probing.

**SSDPScanPhase:**
- `SSDPSocketSearch` sends the M-SEARCH to 239.255.255.250:1900 from an unconnected, non-blocking BSD UDP socket and reads replies from any sender for 3 seconds, on its own queue; cancelling ends the window early. The socket is bound (`IP_BOUND_IF`, `IP_MULTICAST_IF`) to the interface of `context.localIP` when known. Do not go back to a UDP `NWConnection` to the group: it is connected to the group address and drops the devices' unicast replies (it received none on macOS, #387).
- Reads each responder's description from its `LOCATION` (`UPnPDescriptionFetcher`, `UPnPDeviceDescription`): plain HTTP to an address in the scan subnet only, 2 s, 64 KB, at most 2 URLs per device, 4 at a time. Fills `friendlyName`, `manufacturer`, `modelName` on the device (#387).
- Logs (`os.Logger` category `SSDP`, errno values and counts only) socket, send and poll failures and responder/description counts. On iPhone a send failure is the sign of a missing multicast entitlement (#381).
- Weight: 0.06.

**ReverseDNSScanPhase:**
- DNS PTR lookups via `DeviceNameResolver` (`getnameinfo`).
- Enriches discovered devices with hostnames; upserts pass `confirmsPresence: false` (a name is not evidence the device is present).
- Sequential execution (not parallelized).
- Weight: 0.08.

### Presence and the cached state (#378)

A device is online only with evidence from this scan: an answer (ICMP, TCP connect or RST, Bonjour, SSDP, Mac companion, open port) or a refreshed ARP entry. `ScanAccumulator` tracks the rest as unconfirmed, and its snapshots set `DiscoveredDevice.isCached = true` for them. The apps show these as "Cached" (macOS `DeviceStatus.cached`). Enrichment phases that only add data (names, vendor, reverse DNS) must upsert with `confirmsPresence: false`.

### Working Instructions

1. **Adding a New Phase:** Implement `ScanPhase` protocol, add to `ScanPipeline.standard()` in appropriate step. Pass `confirmsPresence: false` to `upsert` unless the device answered your phase.
2. **RTT-Based Timeouts:** Use `await context.rttTracker?.calculateTimeout()` for adaptive timeouts. Fallback to static timeout if tracker unavailable.
3. **Progress Reporting:** Call `onProgress()` callback with 0.0–1.0 as work completes. ScanEngine aggregates this with phase weights.
4. **Cancellation:** Check `context.isCancelled()` in loops to support early termination.
5. **Thermal Awareness:** Wrap connection creation in `withConnectionSlot { ... }` — it holds a budget slot for the body and releases it on every exit path. Budget auto-adjusts based on thermal state.

### Testing

Test phases via integration tests in parent project:
```bash
xcodebuild test -scheme Netmonitor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Dependencies

- Foundation (Process, Timer, RunLoop)
- Network.framework (NWConnection for TCP probes)
- Darwin (`getnameinfo` for reverse DNS, `sysctl` for the ARP table)
- CFNetwork (NetService for Bonjour)

### Pipeline order and weights

`ScanPipeline.standard()` runs five steps:

1. ARP (0.10) + Bonjour (0.13), concurrent
2. TCP probe (0.55) + SSDP (0.06), concurrent
3. ICMP latency (0.10)
4. ARP re-check (0.01)
5. Reverse DNS (0.08)

Platforms may append trailing steps (macOS adds its enrichment step: name resolution, vendor lookup, quick port scan, shell ping).
