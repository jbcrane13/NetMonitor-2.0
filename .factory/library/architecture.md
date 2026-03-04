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
- **Phase 3 (WiFiman)**: blue (-30 to -50) → green (-50 to -60) → yellow (-60 to -70) → orange (-70 to -80) → red (-80 to -90+)

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
