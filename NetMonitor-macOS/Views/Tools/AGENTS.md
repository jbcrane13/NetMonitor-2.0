<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Views/Tools

## Purpose
Network diagnostic tool views for macOS. Each tool is presented as a sheet from `ToolsView`. Tools share the same functional design as iOS but use macOS-native layout (no liquid glass theme).

## Key Files

| File | Description |
|------|-------------|
| `ToolSheetContainer.swift` | Common sheet wrapper with toolbar (close, copy results) |
| `PingToolView.swift` | Streaming ping with live result table |
| `PortScannerToolView.swift` | Port scan with concurrent results list |
| `TracerouteToolView.swift` | Hop-by-hop traceroute table |
| `DNSLookupToolView.swift` | DNS record query with record type picker |
| `WHOISToolView.swift` | WHOIS lookup with formatted output |
| `BonjourBrowserToolView.swift` | Bonjour service browser with service details |
| `WakeOnLanToolView.swift` | Magic packet sender with MAC address input |
| `SpeedTestToolView.swift` | Download/upload speed test with gauge display |

## For AI Agents

### macOS Tool Pattern
- Tools are sheets — always wrap in `ToolSheetContainer` for consistent chrome
- Service protocols from `NetMonitorCore` are injected via `@Environment`
- Use `Table` (macOS 13+) for result lists with sortable columns where appropriate
- Input validation: disable the run button until input is non-empty and valid
- Streaming results: consume `AsyncStream` inside a `Task` stored in the ViewModel; cancel on dismiss

### Dependencies
- Service protocols: `NetMonitorCore/Services/ServiceProtocols.swift`
- Implementations: `../Platform/` (macOS-specific services)

<!-- MANUAL: -->
