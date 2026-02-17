# NetworkScanKit Phases

**Parent:** [../AGENTS.md](../AGENTS.md)
**Generated:** 2026-02-15

## Purpose

Concrete implementations of network discovery techniques. Each phase conforms to `ScanPhase` and performs a specific discovery method (ARP cache reading, Bonjour/mDNS discovery, TCP probing, SSDP multicast, reverse DNS lookups).

## Key Files

| File | Purpose |
|------|---------|
| `ARPScanPhase.swift` | Parses system ARP cache (`/usr/sbin/arp -an`) for IP-MAC mappings |
| `BonjourScanPhase.swift` | Discovers mDNS/Bonjour services with adaptive exit timeout |
| `TCPProbeScanPhase.swift` | TCP connect probes to common ports with RTT-adaptive timeouts |
| `SSDPScanPhase.swift` | SSDP (UPnP) multicast discovery with configurable overlap duration |
| `ReverseDNSScanPhase.swift` | DNS PTR lookups to resolve hostnames for discovered IPs |

## For AI Agents

### Phase-Specific Patterns

**ARPScanPhase:**
- Executes `/usr/sbin/arp -an` via `Process` and parses output for IP/MAC pairs.
- Lightweight and fast (weight: 1.0).
- No network I/O, purely local cache reading.

**BonjourScanPhase:**
- Uses `NetService` and `NetServiceBrowser` for mDNS discovery.
- Adaptive exit timeout: waits until no new services found for N seconds.
- Supports custom service type filtering (default: `_services._dns-sd._udp`).
- Moderate weight: 2.0.

**TCPProbeScanPhase:**
- Probes common ports (22, 80, 443, 445, etc.) via `NWConnection`.
- Queries `RTTTracker` for adaptive timeout calculation (P90 + buffer).
- Respects `ConnectionBudget` for thermal throttling.
- Highest weight: 10.0 (most time-consuming).
- Uses `withThrowingTaskGroup` for concurrent probing.

**SSDPScanPhase:**
- Sends SSDP M-SEARCH multicast to 239.255.255.250:1900.
- Listens for UPnP device responses.
- Configurable overlap duration (default: 3 seconds past Bonjour).
- Weight: 3.0.

**ReverseDNSScanPhase:**
- DNS PTR lookups via `host` command or `gethostbyaddr`.
- Enriches discovered devices with hostnames.
- Sequential execution (not parallelized).
- Weight: 2.0.

### Working Instructions

1. **Adding a New Phase:** Implement `ScanPhase` protocol, add to `ScanPipeline.standard()` in appropriate step.
2. **RTT-Based Timeouts:** Use `await context.rttTracker?.calculateTimeout()` for adaptive timeouts. Fallback to static timeout if tracker unavailable.
3. **Progress Reporting:** Call `onProgress()` callback with 0.0–1.0 as work completes. ScanEngine aggregates this with phase weights.
4. **Cancellation:** Check `context.isCancelled()` in loops to support early termination.
5. **Thermal Awareness:** Use `ConnectionBudget.acquire()` before creating connections, `release()` when done. Budget auto-adjusts based on thermal state.

### Testing

Test phases via integration tests in parent project:
```bash
xcodebuild test -scheme Netmonitor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Dependencies

- Foundation (Process, Timer, RunLoop)
- Network.framework (NWConnection for TCP probes)
- Darwin (gethostbyaddr for reverse DNS)
- CFNetwork (NetService for Bonjour)

### Phase Weights

- ARP: 1.0 (instant, local cache)
- Bonjour: 2.0 (mDNS discovery, adaptive timeout)
- TCP Probe: 10.0 (most time-consuming, full subnet scan)
- SSDP: 3.0 (multicast with timeout)
- Reverse DNS: 2.0 (PTR lookups)

Total weight in `ScanPipeline.standard()`: 18.0
