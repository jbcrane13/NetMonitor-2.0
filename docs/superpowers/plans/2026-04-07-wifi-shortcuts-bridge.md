# WiFi Shortcuts Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS Shortcuts WiFi bridge fully functional by adding missing entitlements/plist config, a guided setup UI, and fallback-mode indicators.

**Architecture:** The bridge code (`ShortcutsWiFiProvider`, `IOSHeatmapService`, `DeepLinkRouter`) already exists. This plan fixes infrastructure gaps (App Group entitlement, `LSApplicationQueriesSchemes`), adds a setup sheet for first-time Shortcut installation, and wires fallback-mode indicators into the existing HUD and sidebar.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, Swift Testing

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `project.yml` | Modify (lines 139-142, ~175) | Add App Group entitlement + LSApplicationQueriesSchemes |
| `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements` | Modify | Add application-groups array |
| `NetMonitor-iOS/Platform/AppSettings.swift` | Modify (lines 42-54) | Add shortcut setup keys |
| `NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift` | Create | Guided shortcut installation sheet |
| `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift` | Modify (lines 8-17, 200-275) | Present setup sheet + fallback HUD |
| `NetMonitor-iOS/Views/Heatmap/HeatmapSidebarSheet.swift` | Modify (lines 97-113) | Add Wi-Fi setup button + fallback banner |
| `Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift` | Create | Setup state machine + fallback logic tests |

---

### Task 1: Add App Group Entitlement and LSApplicationQueriesSchemes

**Files:**
- Modify: `project.yml:139-142` (entitlements properties)
- Modify: `project.yml:~175` (Info.plist properties, after NSLocalNetworkUsageDescription)
- Modify: `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements`

- [ ] **Step 1: Add App Group to project.yml entitlements**

In `project.yml`, find the iOS entitlements section (line 139-142) and add the application-groups property:

```yaml
    entitlements:
      path: NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements
      properties:
        com.apple.developer.networking.wifi-info: true
        com.apple.security.application-groups:
          - group.com.blakemiller.netmonitor
```

- [ ] **Step 2: Add LSApplicationQueriesSchemes to project.yml Info.plist**

In `project.yml`, in the iOS target's `info.properties` section (after the `NSLocalNetworkUsageDescription` line ~174), add:

```yaml
        LSApplicationQueriesSchemes:
          - shortcuts
```

- [ ] **Step 3: Update the entitlements plist file directly**

Replace the contents of `NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.networking.wifi-info</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.blakemiller.netmonitor</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Regenerate xcodeproj**

Run: `cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate`
Expected: "Generated project" with no errors.

- [ ] **Step 5: Verify entitlement in generated project**

Run: `grep -A 2 "application-groups" NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements`
Expected: Shows the `group.com.blakemiller.netmonitor` string.

Run: `grep "LSApplicationQueriesSchemes" NetMonitor-2.0.xcodeproj/project.pbxproj || echo "Check Info.plist instead"`

- [ ] **Step 6: Build to verify no regressions**

Run: `xcodebuild -scheme NetMonitor-iOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add project.yml NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements NetMonitor-2.0.xcodeproj
git commit -m "fix: add App Group entitlement and LSApplicationQueriesSchemes for Shortcuts WiFi bridge"
```

---

### Task 2: Add AppSettings Keys for Shortcut Setup

**Files:**
- Modify: `NetMonitor-iOS/Platform/AppSettings.swift:42-54`

- [ ] **Step 1: Add shortcut setup keys to AppSettings.Keys**

In `AppSettings.swift`, after the Widget keys section (line 53), add:

```swift
        // MARK: Wi-Fi Shortcut Setup
        static let hasSeenShortcutSetup    = "hasSeenShortcutSetup"
        static let shortcutInstallURL      = "shortcutInstallURL"
```

- [ ] **Step 2: Add default shortcut URL constant to AppSettings**

After the `appGroupSuiteName` constant (line 8), add:

```swift
    /// iCloud link for the companion "Wi-Fi to NetMonitor" Shortcut.
    /// Replace with actual iCloud sharing link once created.
    static let defaultShortcutInstallURL = "https://www.icloud.com/shortcuts/PLACEHOLDER"
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-iOS/Platform/AppSettings.swift
git commit -m "feat: add AppSettings keys for WiFi Shortcut setup flow"
```

---

### Task 3: Write Tests for WiFi Shortcut Setup

**Files:**
- Create: `Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift`

- [ ] **Step 1: Write tests for the setup state machine and preferences**

Create `Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift`:

```swift
import Testing
@testable import NetMonitor_iOS

// MARK: - WiFiShortcutSetupState Tests

@MainActor
struct WiFiShortcutSetupStateTests {

    @Test("initial state is install")
    func initialStateIsInstall() {
        let state = WiFiShortcutSetupState()
        #expect(state.currentStep == .install)
        #expect(state.testResult == nil)
    }

    @Test("startTest transitions to testing state")
    func startTestTransitionsToTesting() {
        let state = WiFiShortcutSetupState()
        state.startTest()
        #expect(state.currentStep == .testing)
    }

    @Test("testSucceeded transitions to success with reading data")
    func testSucceededTransitionsToSuccess() {
        let state = WiFiShortcutSetupState()
        state.startTest()
        let reading = WiFiShortcutSetupState.TestReading(
            ssid: "MyNetwork",
            rssi: -45,
            channel: 6,
            band: "2.4 GHz"
        )
        state.testSucceeded(reading: reading)
        #expect(state.currentStep == .success)
        #expect(state.testResult?.ssid == "MyNetwork")
        #expect(state.testResult?.rssi == -45)
    }

    @Test("testFailed transitions to failed state")
    func testFailedTransitionsToFailed() {
        let state = WiFiShortcutSetupState()
        state.startTest()
        state.testFailed()
        #expect(state.currentStep == .failed)
    }

    @Test("reset returns to install state")
    func resetReturnsToInstall() {
        let state = WiFiShortcutSetupState()
        state.startTest()
        state.testFailed()
        state.reset()
        #expect(state.currentStep == .install)
        #expect(state.testResult == nil)
    }
}

// MARK: - Shortcut Setup Preference Tests

@MainActor
struct ShortcutSetupPreferenceTests {

    @Test("hasSeenShortcutSetup defaults to false")
    func hasSeenSetupDefaultsFalse() {
        let defaults = UserDefaults(suiteName: "test-shortcut-setup")!
        defaults.removePersistentDomain(forName: "test-shortcut-setup")
        let value = defaults.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
        #expect(value == false)
    }

    @Test("hasSeenShortcutSetup can be set to true")
    func hasSeenSetupCanBeSetTrue() {
        let defaults = UserDefaults(suiteName: "test-shortcut-setup-2")!
        defaults.removePersistentDomain(forName: "test-shortcut-setup-2")
        defaults.setBool(true, forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
        #expect(defaults.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup) == true)
    }

    @Test("defaultShortcutInstallURL is a valid URL")
    func defaultInstallURLIsValid() {
        let url = URL(string: AppSettings.defaultShortcutInstallURL)
        #expect(url != nil)
    }
}

// MARK: - ShortcutsWiFiReading Decoding Tests

struct ShortcutsWiFiReadingDecodingTests {

    @Test("decodes valid JSON with all fields")
    func decodesValidJSON() throws {
        let json = """
        {
            "ssid": "TestNetwork",
            "bssid": "AA:BB:CC:DD:EE:FF",
            "rssi": -52,
            "noise": -90,
            "channel": 36,
            "txRate": 866.0,
            "rxRate": 780.0,
            "wifiStandard": "Wi-Fi 6",
            "timestamp": "2026-04-07T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reading = try decoder.decode(ShortcutsWiFiReading.self, from: Data(json.utf8))
        #expect(reading.ssid == "TestNetwork")
        #expect(reading.rssi == -52)
        #expect(reading.noise == -90)
        #expect(reading.channel == 36)
        #expect(reading.txRate == 866.0)
        #expect(reading.wifiStandard == "Wi-Fi 6")
    }

    @Test("decodes JSON with null wifiStandard")
    func decodesNullWifiStandard() throws {
        let json = """
        {
            "ssid": "TestNetwork",
            "bssid": "AA:BB:CC:DD:EE:FF",
            "rssi": -65,
            "noise": -85,
            "channel": 1,
            "txRate": 144.0,
            "rxRate": 130.0,
            "wifiStandard": null,
            "timestamp": "2026-04-07T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reading = try decoder.decode(ShortcutsWiFiReading.self, from: Data(json.utf8))
        #expect(reading.wifiStandard == nil)
    }
}

// MARK: - WiFiInfo Conversion Tests

struct ShortcutsWiFiInfoConversionTests {

    @Test("wifiInfo converts reading to WiFiInfo with correct band")
    func convertsReadingToWiFiInfo() {
        let reading = ShortcutsWiFiReading(
            ssid: "MyNet",
            bssid: "11:22:33:44:55:66",
            rssi: -45,
            noise: -90,
            channel: 6,
            txRate: 300.0,
            rxRate: 280.0,
            wifiStandard: "Wi-Fi 5",
            timestamp: Date()
        )
        let info = ShortcutsWiFiProvider.wifiInfo(from: reading)
        #expect(info.ssid == "MyNet")
        #expect(info.signalDBm == -45)
        #expect(info.noiseLevel == -90)
        #expect(info.channel == 6)
        #expect(info.band == .band2_4GHz)
        #expect(info.linkSpeed == 300.0)
    }

    @Test("wifiInfo infers 5GHz band from channel 36")
    func infers5GHzBand() {
        let reading = ShortcutsWiFiReading(
            ssid: "Net5G",
            bssid: "AA:BB:CC:DD:EE:FF",
            rssi: -55,
            noise: -88,
            channel: 36,
            txRate: 866.0,
            rxRate: 800.0,
            wifiStandard: nil,
            timestamp: Date()
        )
        let info = ShortcutsWiFiProvider.wifiInfo(from: reading)
        #expect(info.band == .band5GHz)
        #expect(info.frequency == "5180 MHz")
    }

    @Test("rssiToPercent maps -100 to 0 and -30 to 100")
    func rssiToPercentBounds() {
        let reading100 = ShortcutsWiFiReading(
            ssid: "X", bssid: "X", rssi: -100, noise: -90,
            channel: 1, txRate: 0, rxRate: 0, wifiStandard: nil, timestamp: Date()
        )
        let reading30 = ShortcutsWiFiReading(
            ssid: "X", bssid: "X", rssi: -30, noise: -90,
            channel: 1, txRate: 0, rxRate: 0, wifiStandard: nil, timestamp: Date()
        )
        let info100 = ShortcutsWiFiProvider.wifiInfo(from: reading100)
        let info30 = ShortcutsWiFiProvider.wifiInfo(from: reading30)
        #expect(info100.signalStrength == 0)
        #expect(info30.signalStrength == 100)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (state type doesn't exist yet)**

Run: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests/WiFiShortcutSetupStateTests 2>&1 | tail -10"`
Expected: Compilation failure — `WiFiShortcutSetupState` not found.

Note: The `ShortcutsWiFiReading` decoding and conversion tests should compile and pass since those types already exist. Run them separately to confirm:

Run: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests/ShortcutsWiFiReadingDecodingTests -only-testing:NetMonitor-iOSTests/ShortcutsWiFiInfoConversionTests 2>&1 | tail -10"`
Expected: All 5 tests PASS.

- [ ] **Step 3: Commit test file**

```bash
git add Tests/NetMonitor-iOSTests/WiFiShortcutSetupTests.swift
git commit -m "test: add WiFi Shortcut setup state machine and reading conversion tests"
```

---

### Task 4: Implement WiFiShortcutSetupState and WiFiShortcutSetupView

**Files:**
- Create: `NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift`

- [ ] **Step 1: Create the setup state model and view**

Create `NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift`:

```swift
import NetMonitorCore
import SwiftUI

// MARK: - WiFiShortcutSetupState

@MainActor
@Observable
final class WiFiShortcutSetupState {

    enum Step {
        case install
        case testing
        case success
        case failed
    }

    struct TestReading {
        let ssid: String
        let rssi: Int
        let channel: Int
        let band: String
    }

    var currentStep: Step = .install
    var testResult: TestReading?
    var showManualInstructions: Bool = false

    func startTest() {
        currentStep = .testing
        testResult = nil
    }

    func testSucceeded(reading: TestReading) {
        testResult = reading
        currentStep = .success
    }

    func testFailed() {
        currentStep = .failed
    }

    func reset() {
        currentStep = .install
        testResult = nil
    }
}

// MARK: - WiFiShortcutSetupView

struct WiFiShortcutSetupView: View {
    @State private var state = WiFiShortcutSetupState()
    var shortcutsProvider: ShortcutsWiFiProvider?
    var onDismiss: () -> Void
    var onSkip: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    switch state.currentStep {
                    case .install:
                        installSection
                    case .testing:
                        testingSection
                    case .success:
                        successSection
                    case .failed:
                        failedSection
                    }
                }
                .padding(Theme.Layout.screenPadding)
            }
            .themedBackground()
            .navigationTitle("Wi-Fi Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        markSeen()
                        onSkip()
                    }
                    .accessibilityIdentifier("shortcutSetup_button_skip")
                }
            }
        }
        .accessibilityIdentifier("shortcutSetup_screen")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Colors.accent)
                .symbolEffect(.pulse, options: .repeating)

            Text("Wi-Fi Signal Setup")
                .font(.title2.bold())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Install a companion Shortcut to get accurate\nWi-Fi signal readings for heatmap surveys.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Install Step

    private var installSection: some View {
        VStack(spacing: 16) {
            // Feature highlights
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "antenna.radiowaves.left.and.right", text: "Real RSSI in dBm (not estimates)")
                featureRow(icon: "waveform.path", text: "Noise floor and SNR calculation")
                featureRow(icon: "dot.radiowaves.right", text: "Channel, band, and link speed")
            }
            .padding()
            .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: 0)

            // Add Shortcut button
            Button {
                openShortcutInstallLink()
            } label: {
                Label("Add Shortcut", systemImage: "plus.app")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("shortcutSetup_button_addShortcut")

            // Build it yourself (expandable)
            DisclosureGroup(isExpanded: $state.showManualInstructions) {
                manualInstructionsContent
            } label: {
                Label("Build It Yourself", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .tint(Theme.Colors.textSecondary)
            .accessibilityIdentifier("shortcutSetup_button_buildYourself")

            // Test button
            Button {
                Task<Void, Never> {
                    await runTest()
                }
            } label: {
                Label("Test Connection", systemImage: "play.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: Theme.Layout.buttonCornerRadius, padding: 0)
            .accessibilityIdentifier("shortcutSetup_button_test")
        }
    }

    // MARK: - Manual Instructions

    private var manualInstructionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            instructionStep(number: 1, text: "Open the Shortcuts app")
            instructionStep(number: 2, text: "Tap + to create a new shortcut")
            instructionStep(number: 3, text: "Name it \"Wi-Fi to NetMonitor\"")
            instructionStep(number: 4, text: "Add \"Get Network Details\" action")
            instructionStep(number: 5, text: "Add \"Get Dictionary Value\" for each field:\nRSSI, Noise, SSID, BSSID, Channel, TX Rate, RX Rate")
            instructionStep(number: 6, text: "Add \"Set Dictionary\" to build a JSON object with all fields plus a timestamp")
            instructionStep(number: 7, text: "Add \"Save File\" action — save to the NetMonitor app group folder as wifi-reading.json")
            instructionStep(number: 8, text: "Add \"Open URL\" action with:\nnetmonitor://wifi-result")
        }
        .padding(.top, 8)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.Colors.accent.opacity(0.8), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: - Testing Step

    private var testingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("Running test measurement...")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("The Shortcuts app will open briefly.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 32)
    }

    // MARK: - Success Step

    private var successSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Wi-Fi Signal Ready!")
                .font(.title3.bold())
                .foregroundStyle(Theme.Colors.textPrimary)

            if let result = state.testResult {
                VStack(spacing: 8) {
                    resultRow(label: "Network", value: result.ssid)
                    resultRow(label: "Signal", value: "\(result.rssi) dBm")
                    resultRow(label: "Channel", value: "\(result.channel)")
                    resultRow(label: "Band", value: result.band)
                }
                .padding()
                .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: 0)
                .accessibilityIdentifier("shortcutSetup_label_result")
            }

            Button {
                markSeen()
                onDismiss()
            } label: {
                Text("Start Surveying")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("shortcutSetup_button_startSurveying")
        }
    }

    // MARK: - Failed Step

    private var failedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Connection Test Failed")
                .font(.title3.bold())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Make sure the \"Wi-Fi to NetMonitor\" shortcut\nis installed and try again.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                state.reset()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .glassCard(cornerRadius: Theme.Layout.buttonCornerRadius, padding: 0)
            .accessibilityIdentifier("shortcutSetup_button_retry")
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func resultRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func openShortcutInstallLink() {
        let urlString = UserDefaults.standard.string(
            forAppKey: AppSettings.Keys.shortcutInstallURL,
            default: AppSettings.defaultShortcutInstallURL
        ) ?? AppSettings.defaultShortcutInstallURL
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func runTest() async {
        state.startTest()
        guard let provider = shortcutsProvider else {
            state.testFailed()
            return
        }
        do {
            if let reading = try await provider.fetchWiFiSignal(timeout: 5.0) {
                let band = reading.channel <= 14 ? "2.4 GHz" :
                           reading.channel <= 177 ? "5 GHz" : "6 GHz"
                state.testSucceeded(reading: .init(
                    ssid: reading.ssid,
                    rssi: reading.rssi,
                    channel: reading.channel,
                    band: band
                ))
            } else {
                state.testFailed()
            }
        } catch {
            state.testFailed()
        }
    }

    private func markSeen() {
        UserDefaults.standard.setBool(true, forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
    }
}
```

- [ ] **Step 2: Run the state machine tests to verify they pass**

Run: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests/WiFiShortcutSetupStateTests -only-testing:NetMonitor-iOSTests/ShortcutSetupPreferenceTests 2>&1 | tail -10"`
Expected: All 7 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-iOS/Views/Heatmap/WiFiShortcutSetupView.swift
git commit -m "feat: add WiFi Shortcut setup view with guided installation flow"
```

---

### Task 5: Wire Setup Sheet into HeatmapSurveyView

**Files:**
- Modify: `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift:8-17` (add state vars)
- Modify: `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift:62-85` (add sheet)
- Modify: `NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift:200-275` (fallback HUD)

- [ ] **Step 1: Add setup sheet state and shortcutsProvider to HeatmapSurveyView**

In `HeatmapSurveyView.swift`, add after line 15 (`@State private var showProjectsList = false`):

```swift
    @State private var showShortcutSetup = false
    @State private var shortcutsProvider = ShortcutsWiFiProvider()
```

- [ ] **Step 2: Add the setup sheet presentation**

In `HeatmapSurveyView.swift`, after the `.sheet(isPresented: $showProjectsList)` block (after line 85), add:

```swift
        .sheet(isPresented: $showShortcutSetup) {
            WiFiShortcutSetupView(
                shortcutsProvider: shortcutsProvider,
                onDismiss: { showShortcutSetup = false },
                onSkip: { showShortcutSetup = false }
            )
            .accessibilityIdentifier("heatmap_sheet_shortcutSetup")
        }
```

- [ ] **Step 3: Trigger setup sheet when starting survey without shortcut**

In `HeatmapSurveyView.swift`, in the `.onAppear` block (line 95), add a check after the deep link handling:

```swift
        .onAppear {
            // Check if a .netmonsurvey file was opened via deep link
            if let url = deepLinkRouter?.consumePendingFile() {
                openFileFromDeepLink(url)
            }
            // Check if shortcut setup should be shown
            Task<Void, Never> {
                let hasSeen = UserDefaults.standard.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
                if !hasSeen {
                    let available = await shortcutsProvider.checkAvailability()
                    if !available {
                        showShortcutSetup = true
                    }
                }
            }
        }
```

- [ ] **Step 4: Update signal HUD for fallback mode**

In `HeatmapSurveyView.swift`, replace the `signalHUD` computed property (lines 222-273) with a version that shows fallback state:

Replace:
```swift
            HStack(spacing: 6) {
                Image(systemName: rssiWiFiIcon(viewModel.currentRSSI))
                    .font(.caption.bold())
                    .foregroundStyle(rssiColor(viewModel.currentRSSI))
                Text("\(viewModel.currentRSSI) dBm")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityIdentifier("heatmap_hud_rssi")
```

With:
```swift
            HStack(spacing: 6) {
                if shortcutsProvider.isAvailable {
                    Image(systemName: rssiWiFiIcon(viewModel.currentRSSI))
                        .font(.caption.bold())
                        .foregroundStyle(rssiColor(viewModel.currentRSSI))
                    Text("\(viewModel.currentRSSI) dBm")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Theme.Colors.textPrimary)
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No Signal Data")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .accessibilityIdentifier("heatmap_hud_rssi")
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -scheme NetMonitor-iOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift
git commit -m "feat: wire WiFi Shortcut setup sheet into heatmap survey with fallback HUD"
```

---

### Task 6: Add Fallback Banner and Setup Button to Sidebar Sheet

**Files:**
- Modify: `NetMonitor-iOS/Views/Heatmap/HeatmapSidebarSheet.swift:8-11` (add property)
- Modify: `NetMonitor-iOS/Views/Heatmap/HeatmapSidebarSheet.swift:97-113` (add banner)

- [ ] **Step 1: Add shortcutsProvider and onSetup callback to HeatmapSidebarSheet**

In `HeatmapSidebarSheet.swift`, update the struct properties (lines 8-11):

```swift
struct HeatmapSidebarSheet: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    var shortcutsProvider: ShortcutsWiFiProvider?
    var onShare: (() -> Void)?
    var onSetup: (() -> Void)?
    @State private var isExpanded = false
```

- [ ] **Step 2: Add fallback banner and setup button to expanded controls**

In `HeatmapSidebarSheet.swift`, in the `expandedControls` computed property (line 97), add the banner before the divider:

```swift
    private var expandedControls: some View {
        VStack(spacing: 12) {
            // Fallback banner when Shortcuts not available
            if shortcutsProvider?.isAvailable != true {
                Button {
                    onSetup?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Install Wi-Fi Shortcut for signal data")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("heatmap_button_shortcutBanner")
            }

            Divider().background(Theme.Colors.divider)

            // Visualization picker
            visualizationPicker

            // Color scheme picker
            colorSchemePicker

            // Opacity slider
            opacitySlider

            // Stats + actions
            statsAndActions
        }
    }
```

- [ ] **Step 3: Update HeatmapSurveyView to pass shortcutsProvider and onSetup to sidebar**

In `HeatmapSurveyView.swift`, update the `HeatmapSidebarSheet` call (line 216):

Replace:
```swift
            HeatmapSidebarSheet(viewModel: viewModel, onShare: { shareHeatmap() })
```

With:
```swift
            HeatmapSidebarSheet(
                viewModel: viewModel,
                shortcutsProvider: shortcutsProvider,
                onShare: { shareHeatmap() },
                onSetup: { showShortcutSetup = true }
            )
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -scheme NetMonitor-iOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NetMonitor-iOS/Views/Heatmap/HeatmapSidebarSheet.swift NetMonitor-iOS/Views/Heatmap/HeatmapSurveyView.swift
git commit -m "feat: add fallback banner and Wi-Fi setup button to heatmap sidebar"
```

---

### Task 7: Run Full Test Suite and Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Regenerate xcodeproj to ensure all new files are included**

Run: `cd /Users/blake/Projects/NetMonitor-2.0 && xcodegen generate`
Expected: "Generated project" with no errors.

- [ ] **Step 2: Build iOS target**

Run: `xcodebuild -scheme NetMonitor-iOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all new tests on Mac mini**

Run: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && git pull && xcodegen generate && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests/WiFiShortcutSetupStateTests -only-testing:NetMonitor-iOSTests/ShortcutSetupPreferenceTests -only-testing:NetMonitor-iOSTests/ShortcutsWiFiReadingDecodingTests -only-testing:NetMonitor-iOSTests/ShortcutsWiFiInfoConversionTests 2>&1 | tail -15"`
Expected: All tests PASS.

- [ ] **Step 4: Run existing heatmap tests to verify no regressions**

Run: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-iOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-iOSTests/HeatmapSurveyViewModelTests -only-testing:NetMonitor-iOSTests/DeepLinkRouterTests 2>&1 | tail -15"`
Expected: All existing tests PASS.

- [ ] **Step 5: Verify entitlement in built app**

Run: `xcodebuild -scheme NetMonitor-iOS -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -i "entitlements" | head -5`

Also verify the plist:
Run: `plutil -p NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements`
Expected: Shows both `com.apple.developer.networking.wifi-info` and `com.apple.security.application-groups`.

- [ ] **Step 6: Final commit of any generated project changes**

```bash
git add NetMonitor-2.0.xcodeproj
git commit -m "chore: regenerate xcodeproj with WiFi Shortcuts bridge changes"
```
