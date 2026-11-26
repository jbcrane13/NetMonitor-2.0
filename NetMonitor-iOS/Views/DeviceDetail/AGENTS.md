<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-15 -->

# DeviceDetail

## Purpose
Device detail view showing comprehensive information about a single network device including network info, services, ports, status, quick actions, and notes.

## Key Files
| File | Description |
|------|-------------|
| `DeviceDetailView.swift` | Comprehensive device detail screen with multiple sections |
| `DeviceInterfacesSection.swift` | Interfaces of a device of several rows (#594): address, MAC, ports, notes, "Grouped by Bonjour name", "Not the same device", "Remove this interface" |
| `DeviceDetailView+Interfaces.swift` | Wake on LAN to every interface's MAC; well-known port names |
| `DeviceDetailView+Grouping.swift` | #594 PR2: suggestion banner, "Same device as…" picker sheet, override confirmation and undo toast (`DeviceGroupingPresentation`). State and actions live in `ViewModels/DeviceDetailViewModel+Grouping.swift` (`DeviceGroupingState`); candidates, search and wording come from Core `DeviceGroupingChoices` |
| `LabelCaptureView.swift` | Scan Label sheet (#456): photo → OCR → on-device model → review → Save as user-confirmed identity; `LabelCaptureViewModel`; Core pipeline in `NetMonitorCore/Insight/LabelReader.swift`. UI-test seams `UITEST_LABEL_IMAGE`, `UITEST_LABEL_MODEL` |

## For AI Agents

### Working In This Directory
- Uses `DeviceDetailViewModel` for state management
- Loads device from SwiftData using `@Environment(\.modelContext)`
- Device is identified by IP address passed as parameter
- View automatically enriches device data on appear (ports, services)
- Accessibility prefix: `deviceDetail_`; the "Same device as…" sheet uses `sameDeviceAs_` (`screen_sameDeviceAs`, `sameDeviceAs_row_<ip>`, `sameDeviceAs_label_empty`, `sameDeviceAs_button_cancel`)
- Grouping IDs (#594 PR2, shared with the Mac): `deviceDetail_banner_suggestion`, `deviceDetail_label_suggestion`, `deviceDetail_button_suggestionSameDevice` / `_suggestionNotSameDevice`, `deviceDetail_button_sameDeviceAs`, `deviceDetail_button_confirmGroupOverride` / `_cancelGroupOverride`, `deviceDetail_toast_undo`, `deviceDetail_label_toastMessage`, `deviceDetail_button_undo`, `deviceDetail_button_dismissToast`, `deviceDetail_button_notSameDevice_<ip>`, `deviceDetail_label_groupedByBonjour_<ip>` (`<ip>` with dots as underscores, like the other interface IDs)

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
