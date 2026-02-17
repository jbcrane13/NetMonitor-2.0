<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-29 | Updated: 2026-02-15 -->

# Tools

## Purpose
Network diagnostic tool views. Each tool has its own view and corresponding ViewModel.

## Key Files
| File | Description |
|------|-------------|
| `ToolsView.swift` | Navigation hub listing all available tools |
| `PingToolView.swift` | TCP ping with streaming results via AsyncStream |
| `PortScannerToolView.swift` | Port scanning interface with concurrent scanning |
| `DNSLookupToolView.swift` | DNS record query interface (A, AAAA, MX, TXT, etc.) |
| `TracerouteToolView.swift` | Network path tracing display with hop visualization |
| `BonjourDiscoveryToolView.swift` | mDNS service browser with service details |
| `WHOISToolView.swift` | WHOIS lookup interface for domain/IP information |
| `WakeOnLANToolView.swift` | Magic packet sender for Wake-on-LAN |
| `SpeedTestToolView.swift` | Network speed test interface with download/upload metrics |
| `WebBrowserToolView.swift` | Network-related web browsing with quick bookmarks |

## For AI Agents

### Working In This Directory
- Each tool view follows the pattern: input field + run button + results list + statistics
- Use shared components: `ToolInputField`, `ToolRunButton`, `ToolResultRow`, `ToolStatisticsCard`, `ToolClearButton`
- Each view owns its ViewModel via `@State`
- Accessibility prefix: `tools_` for ToolsView, `{toolName}_` for specific tools (e.g., `ping_`, `portScanner_`)
- Results can be persisted via `ToolResult` SwiftData model
- Use `GlassCard` for result containers and statistics

### Testing Requirements
- Verify input validation before enabling run button
- Test AsyncStream result handling for ping/port scan
- Ensure results clear correctly
- Test statistics calculations
- Verify accessibility identifiers on all interactive elements

### Common Patterns
- ViewModels are `@MainActor @Observable` classes
- Streaming tools (ping, port scan) use `Task` for AsyncStream consumption
- Results arrays updated on main actor
- Statistics computed from results array
- Empty states show when no results available
- Loading/running states disable input controls

### Dependencies
- ViewModels: `../../ViewModels/` (one per tool)
- Services: `../../Services/PingService.swift`, `../../Services/PortScannerService.swift`, `../../Services/DNSLookupService.swift`, etc.
- Models: `../../Models/ToolResult.swift`, `../../Models/PingResult.swift`, `../../Models/PortScanResult.swift`, etc.
- Components: `../Components/ToolInputField.swift`, `../Components/ToolRunButton.swift`, `../Components/ToolResultRow.swift`, `../Components/ToolStatisticsCard.swift`, `../Components/ToolClearButton.swift`

<!-- MANUAL: -->
