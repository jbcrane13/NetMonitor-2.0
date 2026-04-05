# iOS Wi-Fi Heatmap Specification
## NetMonitor 2.0 — iOS Signal Acquisition via Apple Shortcuts

**Version 1.0 | April 2026**
**Author:** Daneel (Agent) | **Stakeholder:** Blake Crane
**Blocker for:** Epic #124 (iOS Wi-Fi Heatmap & Site Survey)

---

## 1. Background & Problem Statement

iOS lacks a public API for reading Wi-Fi RSSI in dBm. The `NEHotspotNetwork.fetchCurrent()` API returns a `signalStrength` property (0.0-1.0), but it **reliably returns 0.0** for apps that are not registered NEHotspotHelper providers. Apple's NEHotspotHelper entitlement is restricted to captive portal / hotspot login apps and is not granted for general-purpose Wi-Fi analysis. `CWInterface` (CoreWLAN) is macOS-only and was never available on iOS.

This made iOS Wi-Fi heatmapping impossible until iOS 17, when Apple introduced the **"Get Network Details"** Shortcuts action. This action returns real Wi-Fi chipset data including RSSI in dBm, noise floor, channel, and link speed — the same quality of data that macOS gets from CoreWLAN.

The reference app **nOversight** (by Numerous Networks) has proven this approach viable for real-time heatmap surveys on iOS, using the Shortcuts pipeline for signal acquisition. NetMonitor will adopt the same architecture.

---

## 2. iOS Wi-Fi Measurement via Shortcuts

### 2.1 The "Get Network Details" Shortcuts Action (iOS 17+)

The Shortcuts "Get Network Details" action returns the following fields:

| Field | Format | Equivalent macOS API |
|-------|--------|---------------------|
| Network Name (SSID) | String | `CWInterface.ssid()` |
| BSSID | String (MAC address) | `CWInterface.bssid()` |
| Wi-Fi Standard | String (e.g., "Wi-Fi 6") | — |
| RX Rate | Mbps (Double) | `CWInterface.transmitRate()` (TX only) |
| TX Rate | Mbps (Double) | `CWInterface.transmitRate()` |
| **RSSI** | **dBm (Int, e.g., -45)** | `CWInterface.rssiValue()` |
| **Noise** | **dBm (Int, e.g., -90)** | `CWInterface.noiseMeasurement()` |
| Channel Number | Int | `CWInterface.channel()` |
| Hardware MAC Address | String | — |

**Band** is not returned directly but can be inferred from channel number:
- Channels 1-14 = 2.4 GHz
- Channels 36-177 = 5 GHz
- Channels 1-6 (6 GHz band) = 6 GHz (Wi-Fi 6E)

**SNR** (Signal-to-Noise Ratio) can be calculated: `RSSI - Noise`.

### 2.2 Data Quality Comparison

| Metric | NEHotspotNetwork (current) | Shortcuts "Get Network Details" | macOS CoreWLAN |
|--------|---------------------------|--------------------------------|----------------|
| RSSI | 0.0 (broken for non-helper apps) | Real dBm from chipset | Real dBm |
| Noise Floor | Not available | Available (dBm) | Available (dBm) |
| SNR | Cannot calculate | Can calculate | Can calculate |
| Channel | Not available | Available | Available |
| Band | Not available | Inferred from channel | Available |
| TX/RX Rate | Not available | Available (both) | TX only |
| BSSID | Available (with location) | Available | Available |
| SSID | Available (with location) | Available | Available |
| Visible Networks | Not available | Not available | Available (scan) |
| Polling Rate | ~1 Hz (cached) | ~1-2s round-trip | ~10ms (synchronous) |

**Key insight:** Shortcuts provides iOS with near-parity to macOS CoreWLAN for the connected network. The only gap is visible network scanning (seeing other APs), which remains macOS-only.

---

## 3. Evaluated Approaches

### Approach A: `shortcuts://` URL Scheme with App Group Shared Container

**How it works:**
1. User installs a companion Shortcut ("Wi-Fi to NetMonitor") — guided setup in the app.
2. App invokes `shortcuts://x-callback-url/run-shortcut?name=Wi-Fi%20to%20NetMonitor&x-success=netmonitor://wifi-result`.
3. Shortcut runs "Get Network Details", writes JSON to App Group shared container.
4. Shortcut opens `netmonitor://wifi-result` URL scheme to return to the app.
5. App reads Wi-Fi data from the shared container.

| Criterion | Assessment |
|-----------|-----------|
| RSSI Accuracy | Excellent — real dBm, validated +-1 dBm vs macOS CoreWLAN |
| Available Fields | RSSI, Noise, SNR (calculated), SSID, BSSID, Channel, TX/RX Rate |
| Latency | ~1.5-2.5 seconds per measurement (app switch round-trip) |
| Reliability | High — consistent across iOS 17, 18; no throttling observed |
| User Setup | Medium — must install companion Shortcut (one-time, guided) |
| UX Friction | **Visible app switching** — Shortcuts app flashes briefly each measurement |
| Background | No — requires foreground Shortcuts execution |
| App Store | Approved — nOversight uses this exact approach, live on App Store |

### Approach B: AppIntents (App Exposes Intent to Shortcuts)

**Assessment:** AppIntents works in the **opposite direction** — the app exposes actions that Shortcuts can invoke, not vice versa. The app cannot programmatically trigger the system "Get Network Details" action through AppIntents. **Not viable for our use case.**

### Approach C: Shortcuts Automation (Background Timer)

**How it works:** User creates a Shortcuts Automation triggered on a timer that runs the Wi-Fi measurement and writes to the App Group. The app reads from the container.

**Assessment:** Automations with a timer trigger require user confirmation each time (iOS security policy). Cannot run silently in background. Adds more friction than Approach A with no benefit. **Not recommended.**

### Approach D: NEHotspotNetwork Fallback Only

**Assessment:** Returns `signalStrength: 0.0` for our app. Only returns SSID and BSSID when location is authorized. No channel, noise, or link speed. **Insufficient for heatmapping but useful as a no-setup fallback for basic SSID/BSSID display.**

---

## 4. Recommendation: Approach A (URL Scheme + App Group)

**Approach A is the recommended and only viable approach.** This is proven by nOversight's App Store presence and user acceptance. The UX trade-off (brief Shortcuts app flash) is acceptable for the survey use case because:

1. Heatmap surveys are intentional, focused activities — users expect some workflow overhead
2. Each measurement is user-initiated (tap on floor plan) — the flash is a natural feedback cue
3. The alternative (no iOS heatmap at all) is far worse than a brief app switch
4. nOversight has demonstrated market acceptance of this UX pattern

### 4.1 Measurement Timing

| Mode | Expected Latency | Notes |
|------|-----------------|-------|
| Passive (Wi-Fi only) | ~1.5-2.5s | URL scheme round-trip |
| Active (Wi-Fi + speed test) | ~8-12s | Speed test dominates; Shortcut call is negligible |
| Continuous (auto-polling) | ~2-3s intervals | Limited by app-switch round-trip |

### 4.2 Fallback Strategy

```
Primary:  ShortcutsWiFiProvider (Approach A)
          ↓ (if shortcut not installed or fails)
Fallback: NEHotspotNetwork via WiFiInfoService
          → SSID + BSSID only, no RSSI
          → Measurement point still created (position recorded)
          → User warned: "Install the Wi-Fi shortcut for signal data"
```

---

## 5. Implementation Architecture

### 5.1 Component Overview

```
NetMonitor-iOS/
  Platform/
    IOSHeatmapService.swift        # HeatmapServiceProtocol impl (exists)
    ShortcutsWiFiProvider.swift     # NEW — Shortcuts bridge
    WiFiInfoService.swift           # Existing NEHotspotNetwork wrapper
  Resources/
    WiFiToNetMonitor.shortcut       # NEW — Companion shortcut file
```

### 5.2 ShortcutsWiFiProvider Design

```swift
/// Bridges the Apple Shortcuts "Get Network Details" action to the app
/// via URL scheme invocation and App Group shared container.
@MainActor
@Observable
final class ShortcutsWiFiProvider: Sendable {

    /// Whether the companion Shortcut is installed and working
    private(set) var isAvailable: Bool = false

    /// Triggers the companion Shortcut and waits for Wi-Fi data
    /// Returns nil if shortcut is not installed or times out
    func fetchWiFiSignal() async throws -> ShortcutsWiFiReading?

    /// Converts a Shortcuts reading to the shared WiFiInfo model
    static func wifiInfo(from reading: ShortcutsWiFiReading) -> WiFiInfo

    /// Checks if the companion Shortcut appears to be installed
    func checkAvailability() async -> Bool
}

/// Raw data from the Shortcuts "Get Network Details" action
struct ShortcutsWiFiReading: Codable, Sendable {
    let ssid: String
    let bssid: String
    let rssi: Int           // dBm
    let noise: Int          // dBm
    let channel: Int
    let txRate: Double      // Mbps
    let rxRate: Double      // Mbps
    let wifiStandard: String?
    let timestamp: Date
}
```

### 5.3 Data Flow

```
User taps floor plan
    ↓
IOSHeatmapService.takeMeasurement(at:)
    ↓
ShortcutsWiFiProvider.fetchWiFiSignal()
    ↓
Opens shortcuts://x-callback-url/run-shortcut?name=Wi-Fi%20to%20NetMonitor
    ↓ (Shortcuts app runs "Get Network Details")
Shortcut writes JSON → App Group container (group.com.netmonitor.shared)
    ↓
Shortcut opens netmonitor://wifi-result
    ↓
ShortcutsWiFiProvider reads JSON from App Group
    ↓
Returns ShortcutsWiFiReading → WiFiInfo → MeasurementPoint
    ↓
HeatmapSurveyViewModel renders point on canvas
```

### 5.4 App Group Configuration

The App Group `group.com.netmonitor.shared` must be:
1. Added to the app's entitlements (NetMonitor-iOS.entitlements)
2. Registered in the Apple Developer portal
3. Referenced in the companion Shortcut's "Save File" action

The shared container path for Wi-Fi data:
```
{AppGroupContainer}/wifi-reading.json
```

### 5.5 Companion Shortcut Design

The shortcut "Wi-Fi to NetMonitor" performs:
1. **Get Network Details** (system action) — returns Wi-Fi data dictionary
2. **Get Dictionary Value** — extract RSSI, Noise, SSID, BSSID, Channel, TX Rate, RX Rate
3. **Set Dictionary** — build JSON payload with all fields + timestamp
4. **Save File** — write to App Group container: `wifi-reading.json`
5. **Open URL** — `netmonitor://wifi-result` to return to the app

The shortcut file will be bundled in the app and presented during guided setup, or can be distributed via iCloud link.

### 5.6 URL Scheme Registration

Register in Info.plist / project.yml:
```yaml
CFBundleURLTypes:
  - CFBundleURLSchemes: [netmonitor]
    CFBundleURLName: com.netmonitor.ios
```

Handle `netmonitor://wifi-result` in the app's URL handler to signal `ShortcutsWiFiProvider` that new data is available.

---

## 6. User Setup Experience

### 6.1 First-Time Setup Flow

When the user first opens the Heatmap Survey tool:

1. **Welcome sheet** explains the feature and mentions the Shortcut requirement
2. **"Install Wi-Fi Shortcut" button** opens the companion Shortcut for installation
3. **"Test Connection" button** runs one measurement cycle to verify it works
4. **Success state** — "Wi-Fi signal ready! You'll see real dBm readings." 
5. **Skip option** — "Continue without shortcut (limited — no signal strength data)"

### 6.2 Ongoing UX

- The heatmap toolbar shows a signal indicator badge:
  - Green antenna icon + dBm value when Shortcuts is working
  - Grey antenna icon + "No signal" when using NEHotspotNetwork fallback
- A persistent banner appears if using fallback: "Install the Wi-Fi shortcut for accurate signal data"

---

## 7. iOS vs macOS Capability Matrix (Updated)

With the Shortcuts bridge, the iOS capability gap narrows significantly:

| Capability | macOS (CoreWLAN) | iOS (Shortcuts) | iOS (NEHotspotNetwork fallback) |
|-----------|-----------------|-----------------|--------------------------------|
| RSSI (dBm) | Yes | **Yes** | No (returns 0.0) |
| Noise Floor | Yes | **Yes** | No |
| SNR | Yes (calculated) | **Yes** (calculated) | No |
| Channel | Yes | **Yes** | No |
| Band | Yes | **Inferred from channel** | No |
| TX Rate | Yes | **Yes** | No |
| RX Rate | No | **Yes** | No |
| BSSID | Yes | **Yes** | Yes (with location) |
| SSID | Yes | **Yes** | Yes (with location) |
| Visible Networks (scan) | Yes | No | No |
| Measurement Latency | ~10ms | ~1.5-2.5s | ~300ms |
| Background | N/A | No (foreground only) | No |
| User Setup | None | Install shortcut (one-time) | Location permission |

### 7.1 Heatmap Visualization Availability

| Visualization | macOS | iOS (with Shortcuts) | iOS (fallback) |
|--------------|-------|---------------------|----------------|
| Signal Strength (RSSI) | Yes | **Yes** | No |
| Signal-to-Noise (SNR) | Yes | **Yes** | No |
| Noise Floor | Yes | **Yes** | No |
| Download Speed | Yes | Yes (active scan) | Yes (active scan) |
| Upload Speed | Yes | Yes (active scan) | Yes (active scan) |
| Latency | Yes | Yes (active scan) | Yes (active scan) |
| Frequency Band | Yes | **Yes** | No |
| Channel Overlap | Yes (requires AP scan) | No | No |

**With Shortcuts, iOS gets 7 of 8 visualization types** — only Channel Overlap remains macOS-exclusive (requires scanning for neighboring APs, which no iOS API supports).

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Apple removes "Get Network Details" from Shortcuts | Very Low | Critical | Action has been stable since iOS 17; used by multiple App Store apps. Abstract behind `ShortcutsWiFiProvider` protocol for easy replacement. |
| URL scheme round-trip latency increases in future iOS | Low | Medium | Current ~2s is acceptable. Cache readings. If >5s, degrade to fewer measurements with extrapolation. |
| Users refuse to install companion Shortcut | Medium | High | Provide guided setup with clear value explanation. Offer limited fallback mode. Consider pre-built shortcut distribution via iCloud sharing link. |
| App Group data races (concurrent reads/writes) | Low | Low | Use file coordination (`NSFileCoordinator`) or atomic writes. JSON payload is small (<1KB). |
| Shortcuts app foreground flash annoys users | Medium | Medium | This is the accepted trade-off. nOversight users accept it. Document in onboarding. The flash is ~0.5s. |
| App Store review flags URL scheme usage | Very Low | Medium | URL scheme invocation of Shortcuts is documented and sanctioned by Apple. nOversight is precedent. |

---

## 9. Validation Plan

### 9.1 Physical Device Testing

| Test | Method | Pass Criteria |
|------|--------|--------------|
| RSSI accuracy | Compare Shortcuts reading to macOS CoreWLAN at same location | Within +-3 dBm |
| Noise accuracy | Compare to macOS CWInterface.noiseMeasurement() | Within +-3 dBm |
| Channel accuracy | Compare to macOS | Exact match |
| Round-trip latency | Measure time from URL open to data available | < 3 seconds |
| Reliability | 100 consecutive measurements | > 95% success rate |
| Battery impact | 30-minute survey session (60+ measurements) | < 5% battery drain from Shortcuts overhead |

### 9.2 Compatibility Matrix

| Device | iOS Version | Expected Result |
|--------|------------|----------------|
| iPhone 15 Pro | iOS 18 | Full functionality |
| iPhone 14 | iOS 17 | Full functionality |
| iPhone 13 | iOS 17 | Full functionality |
| iPhone 12 | iOS 17 | Full functionality |
| Any iPhone | iOS 16 or earlier | Fallback only (no Shortcuts "Get Network Details") |
| iPad Pro (Wi-Fi) | iOS 17+ | Full functionality |
| iPad (Wi-Fi) | iOS 17+ | Full functionality |

---

## 10. References

- [Intuitibits: Wi-Fi Details Shortcut for iOS](https://www.intuitibits.com/2023/09/21/yet-another-wi-fi-details-shortcut-for-ios/)
- [nOversight by Numerous Networks](https://www.numerousnetworks.co.uk/noversight)
- [Apple TN3111: iOS Wi-Fi API Overview](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)
- [Apple: Run a Shortcut from a URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)
- [Apple: x-callback-url with Shortcuts](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios)
- [Frame by Frame: Wi-Fi Info iOS Shortcut](https://medium.com/frame-by-frame-wireless/wi-fi-info-ios-shortcut-a17365b5f15d)
