<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-29 | Updated: 2026-02-15 -->

# Dashboard

## Purpose
Main dashboard tab showing real-time network status overview — connectivity, WiFi info, gateway latency, public IP/ISP details, and discovered devices list.

## Key Files
| File | Description |
|------|-------------|
| `DashboardView.swift` | Primary dashboard layout with status cards and metrics |
| `DeviceListView.swift` | Sortable list of discovered devices with navigation to detail view |

## For AI Agents

### Working In This Directory
- `DashboardView` uses `DashboardViewModel` for state management
- Displays data from multiple services: NetworkMonitorService, WiFiInfoService, GatewayService, PublicIPService
- `DeviceListView` displays devices from NetworkScanKit's `DiscoveredDevice` type
- Use `MetricCard` and `GlassCard` components for consistent styling
- Accessibility prefix: `dashboard_` for DashboardView, `deviceList_` for DeviceListView

### Testing Requirements
- Verify empty states (ContentUnavailableView) with correct accessibility identifiers
- Test device sorting by IP, name, latency, and source
- Ensure NavigationLink destinations work correctly

### Common Patterns
- `DeviceListView` sorts devices using computed property `sortedDevices`
- IP sorting uses custom `.ipSortKey` extension for natural ordering
- Device rows use `GlassCard` for consistent styling
- Navigation to `DeviceDetailView` passes device IP address

### Dependencies
- ViewModels: `../../ViewModels/DashboardViewModel.swift`
- Services: `../../Services/NetworkMonitorService.swift`, `../../Services/WiFiInfoService.swift`, `../../Services/GatewayService.swift`, `../../Services/PublicIPService.swift`
- Models: NetworkScanKit `DiscoveredDevice`
- Components: `../Components/MetricCard.swift`, `../Components/GlassCard.swift`
- Detail View: `../DeviceDetail/DeviceDetailView.swift`

<!-- MANUAL: -->
