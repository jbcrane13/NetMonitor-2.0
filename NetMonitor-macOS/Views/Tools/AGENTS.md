<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Views/Tools

## Purpose
Network diagnostic tool views for macOS. Each tool opens in the main window's detail pane: `ToolsView` sets `selection = .tool(tool)` and `ContentView.toolView(for:)` shows it. Tools share the same functional design as iOS but use macOS-native layout (no liquid glass theme).

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
| `PortForwardsToolView.swift` | Read-only table of the router's UPnP port forwards (#400); state from Core `PortForwardsState` |
| `SecurityReadoutView.swift` | Ranked risks from measured open ports (#454); findings from Core `SecurityRuleTable`, optional model overview via `SecurityReadoutMacViewModel` |
| `TroubleshootToolView.swift` | Guided troubleshooter (#451): symptom → the app's fixed checks with live results → ranked likely causes → optional model explanation; state from Core `TroubleshootState` via `TroubleshootMacViewModel`. AX flow: `scripts/ax/451-troubleshoot.sh` |
| `AskToolView.swift` | Ask your network (#452), in Monitoring and hidden without the model: a question answered by the on-device model through Core `AskToolbox` tools, with citations that open device detail (by `LocalDevice.id`) or the Timeline at the event's day, and the app's freshness line (`AskAnswer.freshness`, from the profile's `lastScanned`); state from Core `AskState` via `AskMacViewModel`. UI tests: `--uitest-ask=answer\|hold\|unavailable` (`Shared/UITest/AskUITestFixture.swift`). AX flow: `scripts/ax/452-ask.sh`. Live tools (#579): `pingDevice` and `networkStatus` (Core `AskLiveTools`) show the app's own lines (`ask_label_measurement_N`); under `--uitest-ask` they use the fixture's fake pinger. AX flow: `scripts/ax/579-ask-live.sh` |

## For AI Agents

### macOS Tool Pattern
- Tools fill the detail pane — always wrap in `ToolSheetContainer` for consistent chrome; its Close calls the `closeTool` environment action (back to the Tools grid, #545)
- Exceptions: Wi-Fi Heatmap (`../Heatmap/WiFiHeatmapView.swift`) and Timeline (`../TimelineView.swift`) are full-pane views without `ToolSheetContainer`, so they have no Close button; the toolbar Back button (`contentView_button_back`) is their only way back to the Tools grid
- Service protocols from `NetMonitorCore` are injected via `@Environment`
- Use `Table` (macOS 13+) for result lists with sortable columns where appropriate
- Input validation: disable the run button until input is non-empty and valid
- Streaming results: consume `AsyncStream` inside a `Task` stored in the ViewModel; cancel on dismiss

### Dependencies
- Service protocols: `NetMonitorCore/Services/ServiceProtocols.swift`
- Implementations: `../Platform/` (macOS-specific services)

<!-- MANUAL: -->
