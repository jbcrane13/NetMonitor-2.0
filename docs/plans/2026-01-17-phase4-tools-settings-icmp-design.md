# Phase 4 Design: Network Tools, Settings UI, and ICMP Monitoring

**Date:** 2026-01-17
**Status:** Approved
**Scope:** Network Tools UI (7 tools), Comprehensive Settings, Shell-based ICMP

---

## Overview

This design covers three major features to complete the NetMonitor application:

1. **Network Tools UI** - Full suite of 7 diagnostic tools
2. **Settings UI** - Comprehensive preferences with 7 sections
3. **ICMP Monitoring** - Shell-based ping replacing the stub implementation

## Architecture

### Component Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                        NetMonitor App                           │
├─────────────────────────────────────────────────────────────────┤
│  Views                                                          │
│  ├── ToolsView (Grid) ──→ Tool Sheets (Ping, Traceroute, etc.) │
│  └── SettingsView (Tabs) ──→ 7 Settings Panels                 │
├─────────────────────────────────────────────────────────────────┤
│  Services                                                       │
│  ├── ShellCommandRunner (shared infrastructure)                 │
│  ├── ProcessPingService (wraps /sbin/ping)                     │
│  └── ICMPMonitorService (delegates to ProcessPingService)      │
├─────────────────────────────────────────────────────────────────┤
│  Utilities                                                      │
│  ├── ContinuationTracker (existing)                            │
│  └── OutputParsers (ping, traceroute, dig output parsing)      │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
ToolsView (Grid) → Tool Sheet → ShellCommandRunner → Parse Output → Display Results
                                     ↓
ICMPMonitorService → ProcessPingService → ShellCommandRunner → TargetMeasurement
```

---

## Network Tools UI

### Grid Layout

7 tools displayed in a 4x2 grid with card-based design:

| Row 1 | Ping | Traceroute | Port Scanner | DNS Lookup |
|-------|------|------------|--------------|------------|
| Row 2 | WHOIS | Speed Test | Bonjour Browser | (empty) |

### Tool Card Design

- Size: 80x80pt cards
- Content: SF Symbol icon, tool name, one-line description
- Style: `.ultraThinMaterial` background, hover highlight
- Interaction: Tap opens sheet presentation

### Common Tool Sheet Layout

```
┌────────────────────────────────────────┐
│ [Tool Name]                      [X]   │  ← Header with close button
├────────────────────────────────────────┤
│ Host: [_____________]  [Run]           │  ← Input area (varies by tool)
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ Results appear here               │ │  ← Scrollable monospace output
│ │ PING 8.8.8.8: 56 bytes...        │ │
│ │ 64 bytes from 8.8.8.8: seq=1...  │ │
│ └────────────────────────────────────┘ │
├────────────────────────────────────────┤
│ Status: Running... [Stop]              │  ← Footer with status/cancel
└────────────────────────────────────────┘
```

Sheet sizes:
- Simple tools (Ping, DNS, WHOIS): 500x400pt
- Complex tools (Port Scanner, Bonjour Browser, Speed Test): 600x500pt

### Individual Tool Specifications

#### 1. Ping
- **Input:** Hostname/IP, count (default 5)
- **Command:** `/sbin/ping -c {count} {host}`
- **Output:** Streams line-by-line, shows summary stats at end
- **Parsing:** Extract seq, ttl, time from each response line

#### 2. Traceroute
- **Input:** Hostname/IP, max hops (default 30)
- **Command:** `/usr/sbin/traceroute -m {maxhops} {host}`
- **Output:** Streams each hop as discovered
- **Note:** Can take 30+ seconds to complete

#### 3. Port Scanner
- **Input:** Hostname/IP, port range or "common ports" preset
- **Implementation:** `Network.framework` NWConnection (not shell)
- **Behavior:** Probes ports concurrently (batch of 50), shows open ports in real-time
- **Common ports:** 22, 80, 443, 8080, 3000, 5000, etc.

#### 4. DNS Lookup
- **Input:** Hostname, record type dropdown (A, AAAA, MX, TXT, CNAME, NS)
- **Command:** `/usr/bin/dig +short {type} {host}`
- **Output:** Parsed and formatted nicely

#### 5. WHOIS
- **Input:** Domain name
- **Command:** `/usr/bin/whois {domain}`
- **Output:** Raw output (already human-readable)

#### 6. Speed Test
- **Implementation:** Uses `speedtest-cli` if available, otherwise fast.com API
- **Output:** Ping latency, download speed, upload speed, server location
- **Duration:** ~30 seconds with progress indicator

#### 7. Bonjour Browser
- **Input:** None (auto-discovers)
- **Implementation:** Uses existing `BonjourDiscoveryService`
- **Display:** Services grouped by type (_http._tcp, _ssh._tcp, etc.)
- **Details:** Name, host, port, TXT records for each service
- **Actions:** Refresh button to rescan

---

## Settings UI

### Window Structure

- Size: 650x450pt
- Layout: Left sidebar (180pt) + content area
- Style: Standard macOS settings patterns

### Tab Structure

```
┌──────────────┬─────────────────────────────────────────┐
│ ● General    │                                         │
│   Monitoring │  [Selected tab content]                 │
│   Notifications                                        │
│   Network    │                                         │
│   Data       │                                         │
│   Appearance │                                         │
│   Companion  │                                         │
└──────────────┴─────────────────────────────────────────┘
```

### Tab Contents

#### General
| Setting | Type | Default |
|---------|------|---------|
| Launch at login | Toggle | Off |
| Show in menu bar | Toggle | On |
| Show in Dock | Toggle | On |

Implementation: Uses `SMAppService` for launch at login.

#### Monitoring
| Setting | Type | Default |
|---------|------|---------|
| Default check interval | Picker (5s, 10s, 30s, 60s) | 30s |
| Default timeout | Picker (3s, 5s, 10s, 30s) | 5s |
| Retry failed checks | Toggle + count | Off, 3 |

#### Notifications
| Setting | Type | Default |
|---------|------|---------|
| Enable notifications | Toggle | On |
| Notify on target down | Toggle | On |
| Notify on target recovery | Toggle | On |
| Latency threshold alert | Slider (100-1000ms) | 500ms |

#### Network
| Setting | Type | Default |
|---------|------|---------|
| Preferred interface | Picker (Auto, Wi-Fi, Ethernet) | Auto |
| Use system proxy | Toggle | On |

#### Data
| Setting | Type | Default |
|---------|------|---------|
| Keep measurement history | Picker (1d, 7d, 30d, Forever) | 7 days |
| Export data | Button | → CSV export |
| Clear all data | Button | → Confirmation alert |

#### Appearance
| Setting | Type | Default |
|---------|------|---------|
| Accent color | ColorPicker | Cyan (#06B6D4) |
| Compact mode | Toggle | Off |

#### Companion
| Setting | Type | Default |
|---------|------|---------|
| Enable companion service | Toggle | On |
| Service port | TextField | 8849 |
| Connected devices | List (read-only) | — |

### Persistence

All settings use `@AppStorage` with keys prefixed `netmonitor.`:
- `netmonitor.general.launchAtLogin`
- `netmonitor.monitoring.defaultInterval`
- etc.

---

## Shell-Based Ping Service

### Why Shell-Based?

macOS App Sandbox blocks raw ICMP sockets. The alternatives are:
1. Privileged helper tool (complex deployment)
2. Disable sandbox (not App Store compatible)
3. **Use `/sbin/ping` via Process** ← Chosen approach

This works within the sandbox, provides accurate results, and unifies the implementation for both target monitoring and the Tools UI.

### New Files

#### ProcessPingService.swift

```swift
actor ProcessPingService {
    /// Single ping, returns aggregate result
    func ping(host: String, count: Int = 1, timeout: TimeInterval = 5) async throws -> PingResult

    /// Stream ping output line-by-line
    func pingStream(host: String, count: Int) -> AsyncThrowingStream<PingLine, Error>
}

struct PingResult: Sendable {
    let transmitted: Int
    let received: Int
    let packetLoss: Double      // percentage 0-100
    let minLatency: Double      // milliseconds
    let avgLatency: Double
    let maxLatency: Double
}

struct PingLine: Sendable {
    let sequenceNumber: Int
    let latency: Double?        // nil if timeout
    let ttl: Int?
    let bytes: Int
    let host: String
}
```

#### Output Parsing

Regex patterns for `/sbin/ping` output:

**Response line:**
```
64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=14.2 ms
```
Pattern: `(\d+) bytes from ([^:]+): icmp_seq=(\d+) ttl=(\d+) time=([0-9.]+) ms`

**Summary line:**
```
5 packets transmitted, 5 received, 0.0% packet loss
```
Pattern: `(\d+) packets transmitted, (\d+) (?:packets )?received, ([0-9.]+)% packet loss`

**Statistics line:**
```
round-trip min/avg/max/stddev = 14.1/15.2/17.8/1.4 ms
```
Pattern: `min/avg/max/stddev = ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms`

### ICMPMonitorService Integration

Update `ICMPMonitorService.check()` to delegate to `ProcessPingService`:

```swift
actor ICMPMonitorService: NetworkMonitorService {
    private let pingService = ProcessPingService()

    func check(target: NetworkTarget) async throws -> TargetMeasurement {
        guard target.targetProtocol == .icmp else {
            throw NetworkMonitorError.invalidHost("Target protocol must be ICMP")
        }

        do {
            let result = try await pingService.ping(
                host: target.host,
                count: 1,
                timeout: target.timeout
            )

            return TargetMeasurement(
                latency: result.avgLatency,
                isReachable: result.received > 0
            )
        } catch {
            return TargetMeasurement(
                latency: nil,
                isReachable: false,
                errorMessage: error.localizedDescription
            )
        }
    }
}
```

### ICMPSocket.swift

Keep for potential future raw socket implementation, but mark unavailable:

```swift
@available(*, unavailable, message: "Use ProcessPingService - raw sockets require elevated privileges")
actor ICMPSocket { ... }
```

---

## Shared Infrastructure

### ShellCommandRunner.swift

Reusable actor for all shell-based tools:

```swift
actor ShellCommandRunner {
    /// Run command and return full output
    func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 30
    ) async throws -> CommandOutput

    /// Run command and stream output line-by-line
    func stream(
        _ executable: String,
        arguments: [String]
    ) -> AsyncThrowingStream<String, Error>

    /// Cancel the currently running command
    func cancel()
}

struct CommandOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: TimeInterval
}
```

### Tool Command Mapping

| Tool | Executable | Arguments |
|------|------------|-----------|
| Ping | `/sbin/ping` | `-c {count} {host}` |
| Traceroute | `/usr/sbin/traceroute` | `-m {maxhops} {host}` |
| DNS Lookup | `/usr/bin/dig` | `+short {type} {host}` |
| WHOIS | `/usr/bin/whois` | `{domain}` |

Port Scanner and Bonjour Browser use `Network.framework`, not shell commands.

### Error Types

```swift
enum ToolError: Error, LocalizedError {
    case commandNotFound(String)
    case timeout(TimeInterval)
    case cancelled
    case executionFailed(exitCode: Int32, stderr: String)
    case parseError(String)

    var errorDescription: String? { ... }
}
```

---

## File Structure

### New Files to Create

```
NetMonitor/
├── Services/
│   ├── ProcessPingService.swift      # Shell-based ping
│   └── ShellCommandRunner.swift      # Shared command execution
├── Views/
│   ├── ToolsView.swift               # Rewrite: Grid launcher
│   ├── Tools/                        # New folder
│   │   ├── PingToolView.swift
│   │   ├── TracerouteToolView.swift
│   │   ├── PortScannerToolView.swift
│   │   ├── DNSLookupToolView.swift
│   │   ├── WHOISToolView.swift
│   │   ├── SpeedTestToolView.swift
│   │   └── BonjourBrowserToolView.swift
│   ├── SettingsView.swift            # Rewrite: Tab-based
│   └── Settings/                     # New folder
│       ├── GeneralSettingsView.swift
│       ├── MonitoringSettingsView.swift
│       ├── NotificationSettingsView.swift
│       ├── NetworkSettingsView.swift
│       ├── DataSettingsView.swift
│       ├── AppearanceSettingsView.swift
│       └── CompanionSettingsView.swift
└── Utilities/
    └── OutputParsers.swift           # Ping, traceroute parsing
```

### Files to Modify

- `ICMPMonitorService.swift` - Delegate to ProcessPingService
- `ICMPSocket.swift` - Mark as unavailable

---

## Implementation Order

### Phase 4a: Infrastructure (Day 1)
1. Create `ShellCommandRunner`
2. Create `ProcessPingService`
3. Update `ICMPMonitorService` to use it
4. Verify ICMP target monitoring works

### Phase 4b: Network Tools (Days 2-3)
1. Rewrite `ToolsView` with grid layout
2. Implement tools in order:
   - Ping (reuses ProcessPingService)
   - DNS Lookup (simple)
   - WHOIS (simple)
   - Traceroute (streaming)
   - Port Scanner (Network.framework)
   - Speed Test (external service)
   - Bonjour Browser (existing service)

### Phase 4c: Settings UI (Day 4)
1. Rewrite `SettingsView` with tab structure
2. Implement tabs in order:
   - General
   - Monitoring
   - Notifications
   - Appearance
   - Data
   - Network
   - Companion

### Phase 4d: Polish (Day 5)
1. Error handling and edge cases
2. Accessibility identifiers
3. Testing
4. Documentation updates

---

## Testing Strategy

### Unit Tests
- `ProcessPingServiceTests` - Output parsing, error handling
- `ShellCommandRunnerTests` - Timeout, cancellation
- `OutputParsersTests` - Regex patterns

### Integration Tests
- ICMP monitoring with real hosts
- Each tool with real commands

### UI Tests
- Tool grid navigation
- Settings persistence
- Sheet presentation/dismissal

---

## Open Questions (Resolved)

1. **ICMP approach?** → Shell-based using `/sbin/ping`
2. **Tools scope?** → Full suite of 7 tools
3. **Settings scope?** → Comprehensive with 7 sections
4. **Tools layout?** → Grid launcher with sheet presentation
5. **Speed test server?** → Public servers (speedtest.net/fast.com)
6. **Bonjour Browser differentiation?** → Service-focused (grouped by type)

---

## Appendix: SF Symbols for Tools

| Tool | Symbol |
|------|--------|
| Ping | `waveform.path` |
| Traceroute | `point.topleft.down.to.point.bottomright.curvepath` |
| Port Scanner | `network` |
| DNS Lookup | `magnifyingglass` |
| WHOIS | `doc.text.magnifyingglass` |
| Speed Test | `speedometer` |
| Bonjour Browser | `bonjour` |
