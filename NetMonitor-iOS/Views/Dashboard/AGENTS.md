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
- `DeviceListView` and `LocalDevicesCard` show the network's saved `LocalDevice` rows through `SavedDeviceList` (#583): each row's `PresenceFreshness` (online, offline, not checked recently) and last-seen time, with past devices behind "Show past devices (N)". They fall back to the live scan's `DiscoveredDevice`s only before any row is saved.
- While the paired Mac's inventory is live (#585: link up, `inventory.v1`, same subnet, recent Mac scan), `SavedDeviceList` takes it as `inventory:` (`MacConnectionService.inventory(for:now:)`): rows read the Mac's state "from your Mac" (`statusText`, `freshness(of:)`, `accessibilityText`), the phone's own sighting as "Seen by this iPhone at …" (`phoneSightingText`), and devices only the Mac knows are `.mac` entries that are shown, never saved or opened. Read presence through the list's methods, not `list.presence`, so every surface agrees.
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
