# WiFi Heatmap Redesign — Design Spec

**Date:** 2026-02-27
**Status:** Approved
**Platforms:** iOS 18+, macOS 15+

---

## Overview

A full redesign of the WiFi Heatmap tool with five improvements: full-screen floor plan canvas (landscape-aware), a skippable scale calibration step, smooth gradient interpolation (replacing isolated dots), toggleable display overlays, and a complete macOS implementation with sidebar stats and hover inspection.

---

## 1. Data Model Changes

### 1.1 `CalibrationScale` (new, in `HeatmapModels.swift`)

```swift
public struct CalibrationScale: Codable, Sendable {
    public let pixelDistance: Double   // px length of drawn reference line
    public let realDistance: Double    // real-world distance entered by user
    public let unit: DistanceUnit      // .feet | .meters

    public var pixelsPerUnit: Double { pixelDistance / realDistance }

    public func realDistance(pixels: Double) -> Double { pixels / pixelsPerUnit }
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case feet = "ft"
    case meters = "m"

    public var displayName: String { rawValue }

    public func convert(_ value: Double, to target: DistanceUnit) -> Double {
        guard self != target else { return value }
        return self == .feet ? value * 0.3048 : value / 0.3048
    }
}
```

### 1.2 `HeatmapSurvey` — add calibration field

```swift
public var calibration: CalibrationScale?  // nil = uncalibrated / skipped
```

### 1.3 `HeatmapColorScheme` (new)

```swift
public enum HeatmapColorScheme: String, Codable, CaseIterable, Sendable {
    case thermal = "thermal"   // blue → cyan → green → yellow → red (DEFAULT)
    case signal  = "signal"    // red → orange → yellow → green
    case nebula  = "nebula"    // navy → violet → magenta → white
    case arctic  = "arctic"    // navy → teal → ice blue → white

    public var displayName: String { ... }
}
```

### 1.4 `HeatmapDisplayOverlay` (new)

```swift
public struct HeatmapDisplayOverlay: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public static let gradient  = HeatmapDisplayOverlay(rawValue: 1 << 0)  // default ON
    public static let dots      = HeatmapDisplayOverlay(rawValue: 1 << 1)
    public static let contour   = HeatmapDisplayOverlay(rawValue: 1 << 2)
    public static let deadZones = HeatmapDisplayOverlay(rawValue: 1 << 3)
}
```

---

## 2. Feature Flow

```
Import Floor Plan  →  [Calibrate Scale]  →  Survey  →  Heatmap View  →  Measurements
       ↑                   (skippable)
  or Freeform Grid
```

### 2.1 Calibration Step (skippable)

Triggered automatically after a floor plan image is imported. Shown as a sheet or overlay.

**Interaction:**
1. Canvas shows the floor plan with instruction: "Drag to draw a reference line between two known points"
2. User drag-draws a line (two endpoints, rendered as cyan dashed line with endpoint handles)
3. Sheet slides up: "How long is this line in real life?" — number input + unit picker (ft / m)
4. "Set Scale" confirms → stores `CalibrationScale` on the survey
5. "Skip" dismisses → survey proceeds uncalibrated (measurements panel omits real-world units)

**Visual feedback:**
- While drawing: live pixel-length counter shown on line ("~ ? ft")
- After confirming: scale bar appears on canvas corner (e.g. `|—— 10 ft ——|`)
- Calibrated surveys show a calibration badge in the survey list

---

## 3. Canvas — Full Screen & Landscape

### 3.1 iOS

- Canvas fixed height removed; replaced with `GeometryReader` filling available space
- **⤢ Full Screen** button → `.fullScreenCover` presenting a dedicated `HeatmapFullScreenView`
  - `ignoresSafeArea()` on all edges
  - Floating translucent control strip at bottom (blur material): scheme picker, overlay toggles, stop/done
  - Landscape: control strip moves to leading edge as a narrow sidebar
- Device rotation handled via `onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification))`

### 3.2 macOS

- Canvas fills the center pane of the three-column layout
- Pinch gesture (trackpad) for zoom; scroll to pan
- Click on canvas → records a data point (same as iOS tap)
- Hover shows a floating tooltip: `−61 dBm · Fair · (12.3 ft, 4.1 ft)` (real units when calibrated)
- Cursor changes to crosshair during active survey

---

## 4. Heatmap Rendering

### 4.1 Gradient Layer (default ON)

Uses SwiftUI `Canvas` with radial gradients and `.screen` blend mode:

```
For each data point:
  1. Map RSSI (−100…−30 dBm) → t (0.0…1.0)
  2. Interpolate color from active scheme's stop table at t
  3. Draw radial gradient: color at center (opacity 0.85) → transparent at radius R
  4. R = clamp(density-adaptive radius, 40pt, 100pt)
  5. BlendMode: .screen (additive-ish, natural blending)
```

Color stop tables defined in `HeatmapColorScheme`. Rendering is pure CPU via `Canvas`; no Metal/Core Image required at typical point counts (< 200 points).

### 4.2 Measurement Dots overlay (default OFF)

Each recorded point rendered as a small labeled circle:
- Circle: 18pt diameter, stroke white, fill = scheme color at that RSSI
- Label below: dBm value in `Space Mono` font (or similar monospace)
- Shown above the gradient layer

### 4.3 Contour Lines overlay (default OFF)

Approximated using marching-squares on a sampled grid:
- Sample grid: 40×40 cells over canvas bounds
- For each cell, interpolate signal using IDW (Inverse Distance Weighting, k=4 nearest points)
- Draw iso-contour paths at thresholds: −50, −65, −80 dBm
- Lines colored by threshold: scheme's strong/fair/weak color respectively
- Labels: small dBm value along the path

### 4.4 Dead Zone Highlight overlay (default OFF)

- Compute same 40×40 IDW grid
- Cells with interpolated RSSI < −75 dBm (or no nearby points within 80pt) → draw pulsing red fill
- Animation: opacity 0.15…0.45, 2s period, easeInOut
- Displayed above all other layers

### 4.5 Scale Bar

Always rendered when calibration is set:
- Bottom-left corner of canvas
- Auto-sized to a "round number" (5 ft, 10 ft, 25 ft, etc.)
- White line with end ticks + label in monospace font

---

## 5. Measurements Panel

### 5.1 Live (during survey)

```
Points recorded: 14        Current: −58 dBm (Fair)
Avg: −55 dBm              Coverage est.: ~42 ft²  [only if calibrated]
```

### 5.2 Post-survey (after Stop)

Full stats card:

| Stat | Value | Notes |
|---|---|---|
| Average signal | −52 dBm | |
| Strongest reading | −38 dBm | |
| Weakest reading | −78 dBm | |
| Measurement count | 18 | |
| Dead zones | 2 | areas < −75 dBm |
| Est. dead zone distance | 3.2 ft | from nearest strong reading; calibrated only |
| Coverage area | 42 ft² | calibrated only |
| Strong coverage % | 87% | area with ≥ −50 dBm |

Units toggle (ft / m) in panel header, persisted to `AppSettings`.

---

## 6. iOS Implementation

### 6.1 `WiFiHeatmapSurveyView` — changes

- Remove fixed `frame(height: 260)` → `GeometryReader` + `maxHeight: .infinity`
- Add `HeatmapFullScreenView` presented via `.fullScreenCover`
- Add calibration sheet: `CalibrationView` (new subview)
- Add `HeatmapControlStrip` (scheme picker + overlay toggles) shown below canvas and in full-screen
- Add `MeasurementsPanel` replacing the current `measurementSection`

### 6.2 `WiFiHeatmapSurveyViewModel` — changes

- Add `calibration: CalibrationScale?`
- Add `colorScheme: HeatmapColorScheme = .thermal`
- Add `displayOverlays: HeatmapDisplayOverlay = .gradient`
- Add `preferredUnit: DistanceUnit = .feet`
- Add `isCalibrating: Bool`, `calibrationStart: CGPoint?`, `calibrationEnd: CGPoint?`
- Add `func setCalibration(pixelDist: Double, realDist: Double, unit: DistanceUnit)`
- Persist `colorScheme`, `preferredUnit`, `displayOverlays` to `AppSettings`

### 6.3 New Views

- `CalibrationView` — draw-line + distance entry UI
- `HeatmapFullScreenView` — fullscreen canvas + floating `HeatmapControlStrip`
- `HeatmapControlStrip` — horizontal strip: scheme picker, overlay toggles, stop/done
- `MeasurementsPanel` — replaces current `measurementSection`, shows full stats table

### 6.4 `HeatmapCanvasView`

Extract the canvas rendering into a standalone `View` shared between normal and full-screen:
- Props: `points`, `floorplanImage`, `colorScheme`, `displayOverlays`, `calibration`, `isSurveying`
- Handles all four rendering layers (gradient, dots, contour, dead zones)
- Emits `onTap(CGPoint, CGSize)` for recording

---

## 7. macOS Implementation

### 7.1 New file: `NetMonitor-macOS/Views/Tools/WiFiHeatmapToolView.swift`

Three-column layout using `NavigationSplitView`:

```
┌─────────────────┬──────────────────────────────┬────────────────────┐
│  Survey List    │  Toolbar + Canvas            │  Signal Stats      │
│  ─────────────  │  ────────────────────────    │  ─────────────     │
│  Survey 3  ●   │  [Thermal][Signal][Nebula]   │  Avg: −52 dBm     │
│  Survey 2      │  [Gradient][Dots][Contour]   │  Min: −78 dBm     │
│  Living Room   │  [Zoom+][Zoom−]             │  Max: −38 dBm     │
│                │                              │  ─────────────     │
│  ─────────────  │  ┌──────────────────────┐   │  Coverage         │
│  Calibrate     │  │                      │   │  87% strong       │
│  New Survey    │  │   [floor plan +      │   │  2 dead zones     │
│                │  │    heatmap canvas]   │   │  ─────────────     │
│                │  │                      │   │  Scale            │
│                │  │                      │   │  1px = 3.2 cm     │
│                │  │   hover tooltip      │   │  (calibrated)     │
│                │  └──────────────────────┘   │  ─────────────     │
│                │  Scale bar (bottom left)     │  Export PNG       │
└─────────────────┴──────────────────────────────┴────────────────────┘
```

### 7.2 macOS-specific capabilities

- **Hover tooltip** — `onContinuousHover` → show dBm + signal level + real coordinates (when calibrated)
- **Zoom & pan** — `MagnificationGesture` + `.offset()` with scroll, reset button
- **Click to record** — `onTapGesture` same normalization as iOS
- **Calibration** — same `CalibrationView` adapted for macOS sheet presentation
- **Export PNG** — render canvas to `NSImage` → save panel → PNG
- **Keyboard shortcut** — `⌘R` to start/stop survey

### 7.3 `WiFiHeatmapService` for macOS

New file: `NetMonitor-macOS/Platform/WiFiHeatmapService.swift`

Signal reading via `CoreWLAN`:
```swift
import CoreWLAN
let iface = CWWiFiClient.shared().interface()
let rssi = iface?.rssiValue()  // Int in dBm
```
Falls back to simulated RSSI if no WiFi interface or entitlement missing.

---

## 8. Persistence

- `HeatmapSurvey` gains `calibration` field — backward-compatible (optional, nil on old surveys)
- `colorScheme`, `preferredUnit`, `displayOverlays` persisted in `AppSettings` as raw values
- Surveys remain in `UserDefaults` (JSON encoded) — unchanged storage key

---

## 9. What Does NOT Change

- `WiFiHeatmapServiceProtocol` interface — unchanged
- `HeatmapDataPoint` struct — unchanged
- `HeatmapSurvey` Codable conformance — backward compatible (new fields optional)
- Existing test suite — should continue to pass; new tests added for new features
- iOS liquid glass UI theme — all new components use `GlassCard`, `Theme.*`

---

## 10. File Manifest

### New files
| File | Purpose |
|---|---|
| `NetMonitor-iOS/Views/Tools/HeatmapCanvasView.swift` | Shared rendering canvas |
| `NetMonitor-iOS/Views/Tools/HeatmapFullScreenView.swift` | Full-screen iOS canvas + control strip |
| `NetMonitor-iOS/Views/Tools/CalibrationView.swift` | Draw-line + distance entry |
| `NetMonitor-iOS/Views/Tools/HeatmapControlStrip.swift` | Scheme + overlay controls |
| `NetMonitor-iOS/Views/Tools/MeasurementsPanel.swift` | Stats display |
| `NetMonitor-macOS/Views/Tools/WiFiHeatmapToolView.swift` | macOS 3-column layout |
| `NetMonitor-macOS/Platform/WiFiHeatmapService.swift` | macOS CoreWLAN signal reading |

### Modified files
| File | Changes |
|---|---|
| `HeatmapModels.swift` | `CalibrationScale`, `DistanceUnit`, `HeatmapColorScheme`, `HeatmapDisplayOverlay`, updated `HeatmapSurvey` |
| `WiFiHeatmapSurveyView.swift` | Remove fixed height, integrate new subviews, full-screen button |
| `WiFiHeatmapSurveyViewModel.swift` | Calibration state, color scheme, overlays, unit preference |
