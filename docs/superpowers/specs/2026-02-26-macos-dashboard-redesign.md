# macOS Dashboard Redesign

## Goal

Replace the current spartan macOS dashboard with an information-dense, network-pro-oriented view inspired by the iOS dashboard and UniFi's network operations aesthetic. Use the full width of the macOS screen to present live graphs, metrics, and monitoring data without clutter.

## Layout: 5-Tier Grid

The dashboard is a `ScrollView > VStack` with 5 logical rows. Each row uses a grid layout to fill horizontal space.

### Row 1: Internet Activity (24H) + Health Gauge

**Left (flex):** `InternetActivityCard`
- 24-hour bandwidth chart (DL + UL as two layered area curves)
- Header: "INTERNET ACTIVITY 24H" + "See All" link
- Stats bar: DL total, UL total, combined total
- Chart: `HistorySparkline`-style area chart, 140pt height, time axis labels
- Time range dots (24H / 7D / 30D — 24H default)
- Data: `MonitoringSession` bandwidth measurements (or simulated if unavailable)

**Right (180pt fixed):** `HealthGaugeCard`
- Circular gauge with gradient arc (emerald → cyan → blue)
- Center: numeric score + "SCORE" label
- Below: status text ("Optimal" / "Degraded" / "Critical")
- Score: calculated from gateway latency, packet loss, device reachability

### Row 2: ISP Health + Latency Analysis

**Left:** `ISPHealthCard`
- ISP name, public IP (monospaced)
- Uptime bar: segmented horizontal bar (green = up, amber = degraded, red = down)
- Uptime % + last outage info
- **Live Throughput** sub-section:
  - Current DL/UL speeds
  - Real-time line chart (DL cyan, UL purple), 70pt height
- Data: `NetworkProfileManager` for ISP/IP, throughput from monitoring session

**Right:** `LatencyAnalysisCard`
- **Gateway Trend (1H):** sparkline showing gateway latency over last 60 minutes
- **Distribution:** histogram bars of last 100 pings, color-coded by latency bucket (<5ms green, 5-20ms cyan, 20-50ms amber, >50ms red)
- **Stats row:** Avg, Min, Max, Jitter, Loss — large monospaced numbers with color coding
- Data: `MonitoringSession` latency history for active gateway target

### Row 3: 4 Mini Metric Cards

4-column `LazyVGrid`, each card is a `MacGlassCard` containing:

| Card | Value | Unit | Sparkline | Data Source |
|------|-------|------|-----------|-------------|
| Gateway Latency | e.g. 2.4 | ms | 20-point latency history | MonitoringSession |
| Signal Strength | e.g. -42 | dBm | 20-point signal history | WiFi info / CoreWLAN |
| WiFi Channel | e.g. 149 | — | Dashed line (static) | CoreWLAN |
| Active Devices | e.g. 14 | — | Device count over time | Device discovery |

Each card: large number (28pt rounded), label, sub-text, mini sparkline (28pt height).

### Row 4: Connectivity + Active Devices

**Left:** `ConnectivityCard`
- ISP row (icon + name)
- Public IP row (icon + monospaced IP)
- DNS row (icon + server list)
- Anchor ping pills: Google, Cloudflare, AWS with latency badges
- Data: `NetworkProfileManager`, DNS from system, anchor pings from periodic probes

**Right:** `ActiveDevicesCard`
- Header: "ACTIVE DEVICES" + "See All" link (navigates to device list)
- Top 5 devices: icon, name, IP (mono), latency badge, status dot
- Data: Device discovery service / scan results

### Row 5: Target Monitoring (full width)

`TargetMonitoringSection` — full-width card containing:
- Header: "TARGET MONITORING" + monitoring status pill
- 3-column `LazyVGrid(columns: adaptive(minimum: 280))`
- Each `TargetStatusCard`:
  - Name (mono, uppercase), status dot
  - Host + protocol
  - Mini sparkline (22pt height) with area fill
  - Latency value + signal status
- START/STOP button toggling `MonitoringSession.isMonitoring`
- Data: SwiftData `NetworkTarget` models + `MonitoringSession` measurements

## Component Breakdown

### New Views to Create
1. `InternetActivityCard` — 24H bandwidth chart with DL/UL
2. `ISPHealthCard` — ISP info, uptime bar, live throughput chart
3. `LatencyAnalysisCard` — gateway trend, histogram, stats row
4. `MiniMetricCard` — reusable card with value + sparkline
5. `ConnectivityCard` — ISP/IP/DNS/anchor pings
6. `ActiveDevicesCard` — top-N device list with latency

### Existing Views to Modify
- `DashboardView` — complete rewrite of body layout
- `TargetStatusCard` — update to 3-column grid layout (from current adaptive)

### Existing Views to Remove
- `InstrumentWidget` (replaced by MiniMetricCard)
- `DeepHistoryGraph` (replaced by InternetActivityCard)

### Reused Components
- `HistorySparkline` (from NetMonitorCore) — for all mini sparklines
- `MacGlassCard` modifier — for all card styling
- `MacThemedBackground` — background (already updated with blue shimmer)

## Data Flow

All data flows through existing observable objects:
- **MonitoringSession** — latency, reachability, bandwidth measurements
- **NetworkProfileManager** — ISP name, public IP, network profiles
- **SwiftData queries** — `NetworkTarget` for target monitoring
- **CoreWLAN** (via existing WiFi service) — SSID, channel, signal strength
- **Device discovery** — active device list from scan results

Where real data isn't available yet (bandwidth history, latency distribution), use realistic simulated data with clear TODO comments for wiring up real sources later.

## Theme

All cards use `MacTheme` tokens:
- Background: `.macGlassCard()` modifier
- Colors: `MacTheme.Colors.*` (success, warning, error, info, textPrimary/Secondary/Tertiary)
- Layout: `MacTheme.Layout.*` constants
- Charts: cyan (#06B6D4) for primary, purple (#8B5CF6) for secondary, green/amber/red for status

## Accessibility

- All interactive elements get `accessibilityIdentifier("dashboard_*")`
- Charts: `accessibilityLabel` with current value description
- Device/target lists: per-item identifiers
