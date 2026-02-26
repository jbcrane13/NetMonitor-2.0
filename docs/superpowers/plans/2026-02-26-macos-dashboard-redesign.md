# macOS Dashboard Redesign Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the macOS DashboardView with an information-dense, 5-tier network operations dashboard inspired by UniFi and the iOS version.

**Architecture:** The dashboard is a single `ScrollView > VStack` with 5 grid rows. Each row contains 1-2 cards implemented as extracted sub-views in the same file. All cards use `MacGlassCard` styling and bind to existing `MonitoringSession`, `NetworkProfileManager`, and SwiftData models. Where real data isn't available yet, use realistic simulated data with TODO comments.

**Tech Stack:** SwiftUI, SwiftData, Charts framework, NetMonitorCore (HistorySparkline), MacTheme tokens

**Spec:** `docs/superpowers/specs/2026-02-26-macos-dashboard-redesign.md`
**Mockup:** `.superpowers/brainstorm/27027-1772090789/dashboard-v2.html`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `NetMonitor-macOS/Views/Dashboard/InternetActivityCard.swift` | 24H bandwidth chart with DL/UL area curves, stats bar, time range selector |
| Create | `NetMonitor-macOS/Views/Dashboard/HealthGaugeCard.swift` | Circular health score gauge with gradient arc |
| Create | `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift` | ISP info, uptime bar, live throughput chart |
| Create | `NetMonitor-macOS/Views/Dashboard/LatencyAnalysisCard.swift` | Gateway trend sparkline, histogram, avg/min/max/jitter/loss stats |
| Create | `NetMonitor-macOS/Views/Dashboard/MiniMetricCard.swift` | Reusable metric card: large value + label + sparkline |
| Create | `NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift` | ISP/IP/DNS rows + anchor ping pills |
| Create | `NetMonitor-macOS/Views/Dashboard/ActiveDevicesCard.swift` | Top-N device list with icons, IPs, latency |
| Rewrite | `NetMonitor-macOS/Views/DashboardView.swift` | New 5-tier layout composing all cards, keep TargetStatusCard + NoTargetsView, remove old widgets |
| Modify | `project.yml` | Add new files to macOS target sources (if XcodeGen glob doesn't auto-include) |

**Note:** `TargetStatusCard` and `NoTargetsView` remain in `DashboardView.swift` since they're tightly coupled to the dashboard. The old `InstrumentWidget`, `DeepHistoryGraph`, `WiFiWidget`, `GatewayWidget`, `SpeedtestWidget`, and `PublicIPWidget` types are removed.

---

## Chunk 1: Foundation — Reusable Cards

### Task 1: Create MiniMetricCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/MiniMetricCard.swift`

This is the reusable building block for Row 3. Build it first so other cards can reference the pattern.

- [ ] **Step 1: Create Dashboard directory**

```bash
mkdir -p NetMonitor-macOS/Views/Dashboard
```

- [ ] **Step 2: Write MiniMetricCard.swift**

Create the file with:
- Props: `title: String`, `value: String`, `unit: String`, `subtitle: String`, `color: Color`, `sparklineData: [Double]`
- Layout: centered VStack — large value (28pt rounded) + unit, label (9pt black tracking), subtitle (10pt mono dim), HistorySparkline (28pt height)
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_metric_\(title.lowercased())")`

Refer to the mockup Row 3 for exact styling. Use `MacTheme.Layout` and `MacTheme.Colors` tokens.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 4: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/MiniMetricCard.swift
git commit -m "feat(macOS): add MiniMetricCard reusable component"
```

### Task 2: Create HealthGaugeCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/HealthGaugeCard.swift`

- [ ] **Step 1: Write HealthGaugeCard.swift**

Create the file with:
- Props: `session: MonitoringSession?`
- Circular gauge using SwiftUI `Circle` with `trim(from:to:)` and `AngularGradient` (emerald → cyan → blue)
- Background track ring at 6% white opacity
- Center overlay: score number (32pt bold rounded) + "SCORE" label (8pt black)
- Below gauge: status text ("Optimal" green / "Degraded" amber / "Critical" red)
- Health score computed from: gateway latency (<20ms=100, <50ms=90, <100ms=70, else 40), adjust if session has packet loss data
- Fixed width: 180pt
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_health_gauge")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/HealthGaugeCard.swift
git commit -m "feat(macOS): add HealthGaugeCard with circular gradient gauge"
```

### Task 3: Create ConnectivityCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift`

- [ ] **Step 1: Write ConnectivityCard.swift**

Create the file with:
- Props: `profileManager: NetworkProfileManager?`
- Three info rows (ISP, Public IP, DNS) each with: icon in 28pt rounded rect background, label (10pt dim), value (12pt mono)
- Anchor ping pills row: HStack of capsule-shaped pills with colored dot + name + latency (monospaced)
- Anchor data: simulated for now (Google 14ms, Cloudflare 8ms, AWS 22ms) with `// TODO: wire to real anchor ping service`
- DNS data: simulated "8.8.8.8, 1.1.1.1" with `// TODO: read from system DNS config`
- ISP/IP data: from `profileManager` where available, fallback to simulated
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_connectivity")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/ConnectivityCard.swift
git commit -m "feat(macOS): add ConnectivityCard with ISP/IP/DNS/anchor pings"
```

### Task 4: Create ActiveDevicesCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ActiveDevicesCard.swift`

- [ ] **Step 1: Write ActiveDevicesCard.swift**

Create the file with:
- Props: `devices: [LocalDevice]` (or whatever the macOS device discovery model is — check `DevicesView.swift` for the pattern)
- Header: "ACTIVE DEVICES" label + "See All" link text (cyan, right-aligned)
- Device rows (top 5): device type icon (SF Symbol mapped from `DeviceType`), name (12pt semibold), IP (10pt mono dim), latency badge (11pt mono green), status dot (7pt circle)
- Row dividers: 1px line at 4% white opacity
- Empty state: "No devices discovered" text
- Simulated data fallback if no real devices: 5 sample entries with `// TODO: wire to device discovery service`
- Wrapped in `.macGlassCard()`
- Accessibility: per-device IDs `accessibilityIdentifier("dashboard_device_\(ip)")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/ActiveDevicesCard.swift
git commit -m "feat(macOS): add ActiveDevicesCard with top-5 device list"
```

---

## Chunk 2: Graph-Heavy Cards

### Task 5: Create InternetActivityCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/InternetActivityCard.swift`

- [ ] **Step 1: Write InternetActivityCard.swift**

Create the file with:
- Props: `session: MonitoringSession?`
- Header row: "INTERNET ACTIVITY" + "24H" dim badge + "See All" right-aligned
- Stats bar: HStack with DL total (bold), UL total (bold), combined total (dim, right-aligned)
- Chart: Use SwiftUI `Charts` framework with:
  - `AreaMark` for download (cyan, 15% opacity fill) + `LineMark` (cyan 1.5pt)
  - `AreaMark` for upload (purple, 12% opacity fill) + `LineMark` (purple 1pt)
  - Y-axis: "Mbps" scale, grid lines at 0.04 white opacity
  - X-axis: time labels (2:00 AM, 8:00 AM, 2:00 PM, 8:00 PM, Now)
  - Chart height: 140pt
  - Recessed background: `Color.black.opacity(0.2)` with 8pt corner radius
- Time range dots: HStack of 3 small circles, first one active (cyan), rest dim
- Data: generate 288 simulated data points (24h * 12 per hour) with `// TODO: wire to real bandwidth monitoring`
  - DL: base ~15 Mbps with random variance, occasional spike to 40-60 Mbps
  - UL: base ~2 Mbps with random variance
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_internet_activity")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/InternetActivityCard.swift
git commit -m "feat(macOS): add InternetActivityCard with 24H bandwidth chart"
```

### Task 6: Create ISPHealthCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`

- [ ] **Step 1: Write ISPHealthCard.swift**

Create the file with:
- Props: `profileManager: NetworkProfileManager?`
- **ISP Health section:**
  - Header: "ISP HEALTH" + "See All" right-aligned
  - ISP name row: satellite emoji + ISP name (13pt semibold) + public IP (11pt mono dim, right-aligned)
  - Uptime bar: horizontal bar with colored segments — use `GeometryReader` with `HStack(spacing: 0)` of colored `Rectangle`s. Segments: 72% green, 3% amber, 25% green. Rounded corners on container (4pt). Height: 8pt.
  - Below bar: "Uptime 99.7%" (green) left, "Last outage 2d 4h ago (3m)" (dim) right
- **Live Throughput sub-section:**
  - Sub-header: "LIVE THROUGHPUT"
  - Stats: down arrow (cyan) + "12.4 Mbps" | up arrow (purple) + "0.8 Mbps"
  - Chart: `HistorySparkline` with 60 data points, 70pt height, cyan color
  - Second trace for upload: if HistorySparkline doesn't support dual traces, overlay two sparklines (cyan DL on top, purple UL behind at lower opacity)
- All data simulated with TODO comments
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_isp_health")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift
git commit -m "feat(macOS): add ISPHealthCard with uptime bar and throughput chart"
```

### Task 7: Create LatencyAnalysisCard

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/LatencyAnalysisCard.swift`

- [ ] **Step 1: Write LatencyAnalysisCard.swift**

Create the file with:
- Props: `session: MonitoringSession?`
- **Layout:** VStack with two side-by-side sections (HStack), then stats row below
- **Left section — Gateway Trend (1H):**
  - Sub-label: "GATEWAY TREND (1H)" (9pt dim)
  - `HistorySparkline` with 60 data points, green color, 60pt height
  - Time labels: "-60m", "-30m", "Now" (8pt mono dim)
  - Data: simulated 60 values around 2-4ms range with `// TODO: wire to MonitoringSession latency history`
- **Right section — Distribution:**
  - Sub-label: "DISTRIBUTION (last 100 pings)" (9pt dim)
  - Histogram: 12 vertical bars using `VStack` inside `HStack`, color-coded:
    - <5ms: green (#10B981)
    - 5-20ms: cyan (#06B6D4)
    - 20-50ms: amber (#F59E0B)
    - >50ms: red (#EF4444)
  - Heights simulate a normal distribution centered around 2-4ms
  - Legend row below: colored squares + bucket labels
  - Data: simulated with `// TODO: compute from real ping results`
- **Stats row** (below, separated by thin divider):
  - HStack of 5 metric values: Avg (green), Min (cyan), Max (amber), Jitter (white), Loss (green)
  - Each: large number (20pt bold rounded) + unit (11pt dim) on top, label (8pt dim) below
  - Simulated: 2.4ms avg, 1.1ms min, 18.3ms max, 0.8ms jitter, 0.0% loss
- Wrapped in `.macGlassCard()`
- Accessibility: `accessibilityIdentifier("dashboard_latency_analysis")`

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/Dashboard/LatencyAnalysisCard.swift
git commit -m "feat(macOS): add LatencyAnalysisCard with trend, histogram, and stats"
```

---

## Chunk 3: Dashboard Assembly

### Task 8: Rewrite DashboardView.swift

**Files:**
- Rewrite: `NetMonitor-macOS/Views/DashboardView.swift`

- [ ] **Step 1: Rewrite DashboardView body**

Replace the entire file. Keep: `TargetStatusCard`, `NoTargetsView`, and the `seedDefaultTargetsIfNeeded()` method. Remove: `DeepHistoryGraph`, `InstrumentWidget`, `WiFiWidget`, `GatewayWidget`, `SpeedtestWidget`, `PublicIPWidget`.

New body layout:

```
ScrollView {
    VStack(spacing: 16) {
        // Row 1: Internet Activity + Health Gauge
        HStack(alignment: .top, spacing: 16) {
            InternetActivityCard(session: session)
            HealthGaugeCard(session: session)
                .frame(width: 180)
        }

        // Row 2: ISP Health + Latency Analysis
        HStack(alignment: .top, spacing: 16) {
            ISPHealthCard(profileManager: profileManager)
            LatencyAnalysisCard(session: session)
        }

        // Row 3: 4 Mini Metric Cards
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            MiniMetricCard(title: "GATEWAY LATENCY", value: "2.4", unit: "ms", ...)
            MiniMetricCard(title: "SIGNAL STRENGTH", value: "-42", unit: "dBm", ...)
            MiniMetricCard(title: "WIFI CHANNEL", value: "149", unit: "", ...)
            MiniMetricCard(title: "ACTIVE DEVICES", value: "\(targets.count)", unit: "", ...)
        }

        // Row 4: Connectivity + Active Devices
        HStack(alignment: .top, spacing: 16) {
            ConnectivityCard(profileManager: profileManager)
            ActiveDevicesCard(devices: [])  // TODO: wire to device discovery
        }

        // Row 5: Target Monitoring (full width)
        VStack(alignment: .leading, spacing: 12) {
            // Header with monitoring pill
            // 3-column LazyVGrid of TargetStatusCards
            // Keep existing TargetStatusCard unchanged except grid columns: adaptive(minimum: 280)
        }
    }
    .padding(20)
}
.macThemedBackground()
.navigationTitle("Dashboard")
```

Wire data from `session`, `profileManager`, `targets` to child cards. Use simulated fallbacks where real data is missing.

Keep `GraphMetric` enum if needed by any child card, otherwise remove.

- [ ] **Step 2: Update TargetStatusCard grid to 3-column**

In the target monitoring section, change from `adaptive(minimum: 220)` to `adaptive(minimum: 280)` for the 3-column layout.

- [ ] **Step 3: Build macOS target**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Fix any compilation errors (missing imports, type mismatches).

- [ ] **Step 4: Build iOS target to verify no regressions**

```bash
xcodebuild -scheme NetMonitor-iOS -configuration Debug build -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 5: Regenerate Xcode project if needed**

If new files aren't picked up by the glob pattern in `project.yml`:

```bash
xcodegen generate
```

Then rebuild both targets.

- [ ] **Step 6: Commit**

```bash
git add NetMonitor-macOS/Views/DashboardView.swift NetMonitor-macOS/Views/Dashboard/
git commit -m "feat(macOS): rewrite dashboard with 5-tier network operations layout

New dashboard sections:
- Internet Activity 24H bandwidth chart
- Health Score gauge
- ISP Health with uptime bar and live throughput
- Latency Analysis with trend, histogram, and stats
- 4 mini metric cards with sparklines
- Connectivity panel with anchor pings
- Active devices list
- Target monitoring in 3-column grid"
```

---

## Chunk 4: Polish and Verify

### Task 9: Visual QA and Fixes

- [ ] **Step 1: Run the macOS app**

```bash
open /Users/blake/Library/Developer/Xcode/DerivedData/NetMonitor-2.0-*/Build/Products/Debug/NetMonitor-macOS.app
```

Or build and run from Xcode. Navigate to Dashboard. Check:
- All 5 rows render without clipping
- Glass cards have proper blur/border
- Sparklines render with Catmull-Rom smoothing
- Health gauge arc renders correctly
- Histogram bars are visible and color-coded
- Uptime bar segments are visible
- Text is readable (not too dim, not too bright)
- Scroll behavior is smooth

- [ ] **Step 2: Fix any visual issues found**

Common issues to watch for:
- Charts overlapping card boundaries → add `.clipped()` or adjust padding
- Sparklines too tall/short → adjust frame heights
- Text truncation → use `.lineLimit(1)` with `.truncationMode(.tail)`
- Missing data crashes → ensure all optionals have fallback display

- [ ] **Step 3: Verify hover effects on target cards still work**

Target cards should still highlight on hover with border glow.

- [ ] **Step 4: Final build check (both targets)**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
xcodebuild -scheme NetMonitor-iOS -configuration Debug build -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 5: Commit any polish fixes**

```bash
git add -A
git commit -m "fix(macOS): dashboard visual polish and layout adjustments"
```

---

## Implementation Notes

### Simulated Data Strategy

Many cards will use simulated data initially. Follow this pattern consistently:

```swift
// TODO: Wire to real bandwidth monitoring data
private var simulatedBandwidthData: [Double] {
    (0..<288).map { _ in Double.random(in: 8...25) }
}
```

This lets the dashboard look complete while real data sources are wired up incrementally in future work.

### Key Imports

Every new dashboard card file needs:
```swift
import SwiftUI
import NetMonitorCore  // for HistorySparkline, model types
```

Cards using Charts framework also need:
```swift
import Charts
```

Cards using SwiftData models need:
```swift
import SwiftData
```

### MacTheme Token Reference

| Usage | Token |
|-------|-------|
| Card background | `.macGlassCard()` modifier |
| Section title | `font: .system(size: 9, weight: .black)`, `tracking: 1.2`, color: `.secondary` |
| Large metric | `font: .system(size: 28, weight: .bold, design: .rounded)` |
| Mono values | `font: .system(size: 12, design: .monospaced)` |
| Dim text | `MacTheme.Colors.textTertiary` or `.foregroundStyle(.secondary)` |
| Success/Warning/Error | `MacTheme.Colors.success / .warning / .error` |
| Primary chart color | `Color(hex: "06B6D4")` (cyan) |
| Secondary chart color | `Color(hex: "8B5CF6")` (purple) |
| Icon accent | `.foregroundStyle(.cyan)` |
