<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-29 | Updated: 2026-02-15 -->

# NetworkMap

## Purpose
Network topology view showing discovered LAN devices and their relationships with real-time discovery controls.

## Key Files
| File | Description |
|------|-------------|
| `NetworkMapView.swift` | Device list/map with discovery controls and scan progress |

## For AI Agents

### Working In This Directory
- Uses `NetworkMapViewModel` for state management
- Integrates with NetworkScanKit for composable scan phases (ARP, TCP, SSDP, Bonjour)
- Device data persisted via `LocalDevice` SwiftData model
- Real-time scan progress tracking with phase-specific feedback
- Accessibility prefix: `map_`

### Testing Requirements
- Verify scan start/stop controls work correctly
- Test empty state when no devices discovered
- Ensure device list updates reactively during scan
- Verify navigation to DeviceDetailView

### Common Patterns
- Scan phases execute in parallel with adaptive timeouts
- Progress indicators for each scan phase
- Device deduplication across scan methods
- SwiftData `@Query` for reactive device list updates

### Dependencies
- ViewModels: `../../ViewModels/NetworkMapViewModel.swift`
- Models: `../../Models/LocalDevice.swift`, NetworkScanKit scan results
- Components: `../Components/GlassCard.swift`, `../Components/StatusBadge.swift`
- Detail View: `../DeviceDetail/DeviceDetailView.swift`
- Package: NetworkScanKit for scan orchestration

<!-- MANUAL: -->
