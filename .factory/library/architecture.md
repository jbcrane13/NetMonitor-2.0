# Architecture

Architectural decisions, patterns discovered, and design rationale.

**What belongs here:** Key architectural decisions, discovered patterns, cross-cutting concerns.

---

## Heatmap Feature Architecture (from PRD)

### Package Placement
| Component | Location |
|-----------|----------|
| HeatmapSurveyModels | `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/` |
| HeatmapServiceProtocol | `Packages/NetMonitorCore/.../Services/ServiceProtocols.swift` |
| WiFiMeasurementEngine | `Packages/NetMonitorCore/.../Services/Heatmap/` |
| HeatmapRenderer | `Packages/NetMonitorCore/.../Services/Heatmap/` |
| macOS Heatmap UI | `NetMonitor-macOS/Views/Heatmap/` |
| iOS Heatmap UI | `NetMonitor-iOS/Views/Heatmap/` |
| iOS AR Services | `NetMonitor-iOS/Services/AR/` (or Platform/AR/) |

### Data Flow
1. Platform WiFiInfoService → WiFiMeasurementEngine → MeasurementPoint
2. [MeasurementPoint] → HeatmapRenderer → CGImage overlay
3. CGImage → SwiftUI Canvas (macOS/iOS Phase 1/2) or Metal texture (iOS Phase 3)

### Color Schemes
- **Phase 1/2 (default)**: green (>=-50 dBm) → yellow (-50 to -70) → red (<=-70)
- **Phase 3 (WiFiman)**: Supports all 5 visualization types with per-visualization normalization ranges:
  - signalStrength: -30 to -90 dBm
  - signalToNoise: 0 to 50 dB
  - downloadSpeed: 0 to 200 Mbps
  - uploadSpeed: 0 to 200 Mbps
  - latency: 0 to 100 ms (inverted — low is good)
  - Color gradient: blue → cyan → green → yellow → orange → red

### File Format (.netmonsurvey)
- Directory bundle (UTI: com.netmonitor.survey)
- Contains: survey.json, floorplan.png, heatmap-cache/ (optional)
- Conforms to: com.apple.package

### macOS Navigation
- Heatmap is a top-level sidebar item via NavigationSection enum in NetMonitorCore
- Case added to NavigationSection.allCases → automatically appears in sidebar

### iOS Navigation
- Heatmap entry in Tools tab via ToolType enum + ToolDestination
- Accessible from ToolsView grid

### IDW Interpolation
- Power parameter: p = 2.0 (Shepard's method)
- Default grid: 200x200
- Default opacity: 70%
- Minimum points: 3
- Performance: <500ms for 50 points, <2s for 200 points

### Known Data Gap: WiFiInfo.linkSpeed

WiFiInfo model in NetMonitorCore lacks a `linkSpeed` field. MacWiFiInfoService reads `transmitRate()` from CoreWLAN but discards it because WiFiInfo has no field for it. WiFiMeasurementEngine.buildMeasurementPoint() consequently sets `linkSpeed: nil` for all measurements. Fixing this requires adding `linkSpeed: Double?` to the WiFiInfo struct in NetMonitorCore.

### macOS ViewModel Size

HeatmapSurveyViewModel.swift has grown to ~950 lines across Phase 1 macOS implementation, triggering SwiftLint's file_length warning. Future features should consider splitting into focused extensions (e.g., `+Undo.swift`, `+Export.swift`, `+Calibration.swift`).

### Logger Category: Heatmap

A `Logger.heatmap` category exists in `NetMonitor-macOS/Platform/Logging.swift` for heatmap feature logging. Some early features used `Logger.app` instead — new code should use `Logger.heatmap`.

### Concurrency Pattern: nonisolated(unsafe) for Non-Sendable Protocol Storage

When an `actor` needs to store a reference to a `@MainActor`-isolated protocol that isn't `Sendable` (e.g., `WiFiInfoServiceProtocol`, `SpeedTestServiceProtocol`), use `nonisolated(unsafe) let` for the stored property. This bypasses actor-isolation checking and is the Swift 6 equivalent of `@unchecked Sendable` for stored properties.

**When to use:** Only when the stored protocol is `@MainActor`-isolated and all accesses go through `await` (ensuring proper isolation at call sites).

**Example (from WiFiMeasurementEngine):**
```swift
public actor WiFiMeasurementEngine: HeatmapServiceProtocol {
    nonisolated(unsafe) let wifiService: any WiFiInfoServiceProtocol
    nonisolated(unsafe) let speedTestService: any SpeedTestServiceProtocol
    let pingService: any PingServiceProtocol // already Sendable — no workaround needed
}
```

**Preferred long-term fix:** Make the protocol itself `Sendable` (add `Sendable` requirement). This eliminates the need for `nonisolated(unsafe)`. The workaround is acceptable when modifying the protocol is outside the current feature scope.
