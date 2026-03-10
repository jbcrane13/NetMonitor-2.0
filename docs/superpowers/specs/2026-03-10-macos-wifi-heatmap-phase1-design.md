# macOS WiFi Heatmap — Phase 1 Design

**Date:** 2026-03-10
**Goal:** Professional-grade WiFi heatmap tool for macOS rivaling NetSpot's core survey workflow.

---

## Layout

Canvas-focused with collapsible 220px signal sidebar (left). Toolbar at top with project name, visualization picker, point count, zoom controls, survey start/stop button, and sidebar collapse toggle. Color legend bar pinned to bottom of canvas.

Sidebar has two modes via segmented control:
- **Survey mode:** Live RSSI meter (large), SSID, BSSID, channel, band, link speed, noise floor, SNR, nearby APs list, Record Point button
- **Analyze mode:** Visualization picker, opacity slider, AP filter dropdown, coverage threshold slider, color scheme picker

## Features (all in scope)

1. Floor plan import (file picker + Photos library via PHPickerViewController)
2. Mandatory scale calibration after import (draw line between two points, enter real distance in ft/m)
3. Live RSSI + noise floor via CoreWLAN (1-second polling)
4. Click-to-record measurement points on canvas
5. Hybrid rendering: color-coded halo dots during survey, full IDW heatmap on "Generate" or survey stop
6. Multiple visualization overlays (Signal, SNR, Noise, Download, Upload, Latency, Channel/Band, AP Coverage)
7. Active scan mode (gateway ping + short speed test per point)
8. Nearby AP list via CoreWLAN scanForNetworks
9. Per-AP heatmap filter (filter by BSSID)
10. Project save/load via ProjectSaveLoadManager (.netmonsurvey format)
11. Export heatmap as PNG/PDF via NSSavePanel
12. Undo last measurement point (Cmd+Z)
13. Hover tooltip on measurement points (all recorded data)
14. Coverage threshold indicator (hatched red overlay below dBm cutoff)
15. Channel/band visualization (categorical color: blue=5GHz, orange=2.4GHz, green=6GHz)
16. Selectable color schemes: Thermal (default), Stoplight, Plasma

## Architecture

### New Components

| Component | Location | Responsibility |
|-----------|----------|---------------|
| `WiFiHeatmapService` | `NetMonitor-macOS/Platform/` | CoreWLAN wrapper — live RSSI, noise floor, SNR, channel, band, link speed, scanForNetworks |
| `WiFiHeatmapViewModel` | `NetMonitor-macOS/ViewModels/` | All state: survey project, measurements, sidebar mode, viz selection, AP filter, undo stack |
| `WiFiHeatmapView` | `NetMonitor-macOS/Views/Heatmap/` | Main view — toolbar + HSplitView(sidebar \| canvas) |
| `HeatmapSidebarView` | `NetMonitor-macOS/Views/Heatmap/` | Collapsible 220px sidebar with Survey/Analyze tabs |
| `HeatmapCanvasView` | `NetMonitor-macOS/Views/Heatmap/` | SwiftUI Canvas for floor plan + overlay + dots + tooltips |

### Enhanced in NetMonitorCore

| Component | Changes |
|-----------|---------|
| `HeatmapModels.swift` | Add `HeatmapColorScheme` enum (thermal/stoplight/plasma) |
| `HeatmapRenderer.swift` | Add 3 gradient schemes, coverage threshold rendering, performance caps |
| `WiFiMeasurementEngine.swift` | Add active mode (speed + latency) |
| `ProjectSaveLoadManager.swift` | Already exists — wire to ViewModel |

### Removed

| Component | Reason |
|-----------|--------|
| `HeatmapSurveyView.swift` (778 lines) | Replaced by WiFiHeatmapView + HeatmapCanvasView + HeatmapSidebarView |
| `HeatmapSurveyViewModel.swift` (492 lines) | Replaced by WiFiHeatmapViewModel |
| `HeatmapProjectListView.swift` (10 lines) | Project management moves to File menu |

## Data Flow

### Survey Workflow
1. Import floor plan (file or Photos) → stored as FloorPlan in SurveyProject
2. Calibration sheet appears immediately (mandatory) — draw line, enter distance
3. Start survey → WiFiHeatmapService begins 1-second CoreWLAN polling
4. Click canvas → captures current signal data + position → creates MeasurementPoint
5. If active mode: runs gateway ping + short speed test before recording (spinner on dot)
6. White dots with color-coded halos appear in real-time (green >-50, yellow -50 to -70, red <-70)
7. Cmd+Z pops last point from undo stack
8. Stop survey or click "Generate Heatmap" → full IDW render

### Analyze Workflow
- Sidebar switches to Analyze tab
- Visualization picker, opacity slider, AP filter, coverage threshold slider
- Changing any control triggers HeatmapRenderer re-render on background thread
- Hover dots shows tooltip with all recorded data
- Coverage threshold draws hatched red overlay on areas below cutoff

### Nearby AP Scanning
- WiFiHeatmapService.scanForNetworks() → CWWiFiClient scanForNetworks(withName: nil)
- Results in collapsible sidebar section — SSID, BSSID, RSSI, channel, band
- Tap AP → sets as AP filter for heatmap

### Project Persistence
- ProjectSaveLoadManager: JSON + embedded floor plan image
- File menu: New Project, Open, Save (Cmd+S), Save As
- .netmonsurvey document type

### Export
- Render canvas to CGImage at 2x (floor plan + overlay + legend + dots)
- NSSavePanel for PNG or PDF

## Renderer Details

### Color Schemes (user-selectable, thermal default)
- **Thermal:** Blue → cyan → green → yellow → red
- **Stoplight:** Red → orange → yellow → green
- **Plasma:** Indigo → purple → red → orange → yellow

### Visualization Value Ranges
| Overlay | Range | Higher = Better |
|---------|-------|----------------|
| Signal Strength | -90 to -30 dBm | Yes |
| Signal-to-Noise | 0 to 50 dB | Yes |
| Noise Floor | -100 to -60 dBm | No |
| Download Speed | 0 to 500 Mbps | Yes |
| Upload Speed | 0 to 500 Mbps | Yes |
| Latency | 0 to 200 ms | No |
| Channel/Band | categorical | Color-coded |
| AP Coverage | categorical | Per-AP zones |

### Performance
- IDW grid: 200x200 default, capped at 400x400 for large floor plans
- Render on background thread, update overlay on completion
- Target: under 500ms for heatmap generation

## Future (not in Phase 1)
- AR mapping: iPhone captures room via ARKit/LiDAR → exports 2D floor plan → Mac imports for heatmapping
- Predictive AP placement planner
- iCloud project sync
