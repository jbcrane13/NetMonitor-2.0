<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-15 -->

# DeviceDetail

## Purpose
Device detail view showing comprehensive information about a single network device including network info, services, ports, status, quick actions, and notes.

## Key Files
| File | Description |
|------|-------------|
| `DeviceDetailView.swift` | Comprehensive device detail screen with multiple sections |

## For AI Agents

### Working In This Directory
- Uses `DeviceDetailViewModel` for state management
- Loads device from SwiftData using `@Environment(\.modelContext)`
- Device is identified by IP address passed as parameter
- View automatically enriches device data on appear (ports, services)
- Accessibility prefix: `deviceDetail_`

### Testing Requirements
- Verify all sections render correctly with populated data
- Test empty states (device not found, no services/ports)
- Ensure loading states show during enrichment
- Verify NavigationLinks to tool views pass correct initial values
- Test TextEditor for notes persists changes to SwiftData
- Verify accessibility identifiers on all interactive elements and sections

### Common Patterns
- View is structured into distinct section methods: `headerSection()`, `networkInfoSection()`, `servicesAndPortsSection()`, `statusSection()`, `quickActionsSection()`, `notesSection()`
- Each section uses `GlassCard` (via `.glassCard()` modifier) for consistent styling
- Info rows use helper method `infoRow(label:value:)` for consistent layout
- Conditional sections render based on data availability
- Action buttons show progress indicators during async operations
- NavigationLinks to tools pass device IP/MAC as initial values

### Key Features
- **Header**: Device icon, name, status badge, manufacturer
- **Network Info**: IP, MAC, hostname, resolved hostname, manufacturer
- **Services & Ports**: Open ports with well-known service names, Bonjour services, scan buttons
- **Status**: Latency with color coding, first/last seen, gateway indicator, Wake-on-LAN support
- **Quick Actions**: NavigationLinks to Ping, Port Scan, DNS Lookup, Wake-on-LAN tools
- **Notes**: TextEditor for freeform notes persisted to SwiftData

### Helper Functions
- `wellKnownServiceName(for:)` maps common ports to service names (SSH, HTTP, HTTPS, etc.)
- `infoRow(label:value:)` creates consistent key-value rows

### Dependencies
- ViewModels: `../../ViewModels/DeviceDetailViewModel.swift`
- Services: `../../Services/PortScannerService.swift`, `../../Services/BonjourDiscoveryService.swift`
- Models: `../../Models/LocalDevice.swift` (SwiftData model)
- Components: `../Components/GlassCard.swift`
- Tool Views: `../Tools/PingToolView.swift`, `../Tools/PortScannerToolView.swift`, `../Tools/DNSLookupToolView.swift`, `../Tools/WakeOnLANToolView.swift`
- Theme: `../../Utilities/Theme.swift`

<!-- MANUAL: -->
