import SwiftUI
import UIKit
import NetMonitorCore

// MARK: - WiFiShortcutSetupState

@MainActor
@Observable
final class WiFiShortcutSetupState {

    enum Step: Equatable {
        case install, testing, success, failed
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
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    headerSection
                    contentSection
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.vertical, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Wi-Fi Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
        VStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: "wifi.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accent)

            Text("Wi-Fi Signal Setup")
                .font(.title2.bold())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Install a companion Apple Shortcut to enable real-time RSSI measurements for accurate heatmap surveys.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Layout.itemSpacing)
    }

    // MARK: - Content routing

    @ViewBuilder
    private var contentSection: some View {
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

    // MARK: - Install Section

    private var installSection: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            featureHighlightsCard
            addShortcutButton
            manualInstructionsDisclosure
            testConnectionButton
        }
    }

    private var featureHighlightsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            featureRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Signal Strength (RSSI)",
                description: "Accurate dBm readings from your current Wi-Fi connection"
            )
            Divider().background(Theme.Colors.divider)
            featureRow(
                icon: "waveform",
                title: "Noise Floor",
                description: "Measures background interference for cleaner heatmaps"
            )
            Divider().background(Theme.Colors.divider)
            featureRow(
                icon: "dot.radiowaves.left.and.right",
                title: "Channel Info",
                description: "Identifies your Wi-Fi channel and frequency band"
            )
        }
        .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Layout.itemSpacing) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var addShortcutButton: some View {
        Button {
            openShortcutInstallLink()
        } label: {
            Label("Add Shortcut", systemImage: "plus.square.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
        }
        .accessibilityIdentifier("shortcutSetup_button_addShortcut")
    }

    private var manualInstructionsDisclosure: some View {
        DisclosureGroup(
            isExpanded: $state.showManualInstructions,
            content: {
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    manualStep(number: 1, text: "Open the Shortcuts app on your iPhone")
                    manualStep(number: 2, text: "Tap the \"+\" button to create a new Shortcut")
                    manualStep(number: 3, text: "Add the action \"Get Network Details\"")
                    manualStep(number: 4, text: "Set it to get \"Wi-Fi Details\"")
                    manualStep(number: 5, text: "Add a \"Dictionary\" action mapping SSID, BSSID, RSSI, Noise, Channel, TX/RX Rate, Wi-Fi Standard")
                    manualStep(number: 6, text: "Add a \"Save File\" action targeting the app group container")
                    manualStep(number: 7, text: "Add an \"Open URL\" action with \"netmonitor://wifi-result\"")
                    manualStep(number: 8, text: "Name the Shortcut exactly: \"Wi-Fi to NetMonitor\"")
                }
                .padding(.top, Theme.Layout.itemSpacing)
            },
            label: {
                Text("Build It Yourself")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        )
        .accessibilityIdentifier("shortcutSetup_button_buildYourself")
        .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)
    }

    private func manualStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Layout.itemSpacing) {
            Text("\(number).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var testConnectionButton: some View {
        Button {
            Task<Void, Never> {
                await runTest()
            }
        } label: {
            Text("Test Connection")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Colors.glassBackground)
                .foregroundStyle(Theme.Colors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                )
        }
        .accessibilityIdentifier("shortcutSetup_button_test")
    }

    // MARK: - Testing Section

    private var testingSection: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.Colors.accent)

            Text("Running test measurement...")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Layout.sectionSpacing * 2)
        .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)
    }

    // MARK: - Success Section

    private var successSection: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            VStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.Colors.success)

                Text("Wi-Fi Signal Ready!")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            if let result = state.testResult {
                VStack(spacing: Theme.Layout.itemSpacing) {
                    resultRow(label: "Network", value: result.ssid)
                    Divider().background(Theme.Colors.divider)
                    resultRow(label: "Signal", value: "\(result.rssi) dBm")
                    Divider().background(Theme.Colors.divider)
                    resultRow(label: "Channel", value: "\(result.channel) (\(result.band))")
                }
                .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)
                .accessibilityIdentifier("shortcutSetup_label_result")
            }

            Button {
                markSeen()
                onDismiss()
            } label: {
                Text("Start Surveying")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.success)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("shortcutSetup_button_startSurveying")
        }
    }

    private func resultRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: - Failed Section

    private var failedSection: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            VStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.Colors.error)

                Text("Connection Test Failed")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Make sure you have added the shortcut and that the Shortcuts app can open. The test will time out after 5 seconds.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)

            Button {
                state.reset()
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.glassBackground)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("shortcutSetup_button_retry")
        }
    }

    // MARK: - Actions

    private func runTest() async {
        state.startTest()

        guard let provider = shortcutsProvider,
              let reading = try? await provider.fetchWiFiSignal(timeout: 5.0) else {
            state.testFailed()
            return
        }

        let band: String
        switch reading.channel {
        case 1...14:   band = "2.4 GHz"
        case 36...177: band = "5 GHz"
        case 233...254: band = "6 GHz"
        default:        band = "Unknown"
        }

        let testReading = WiFiShortcutSetupState.TestReading(
            ssid: reading.ssid,
            rssi: reading.rssi,
            channel: reading.channel,
            band: band
        )
        state.testSucceeded(reading: testReading)
    }

    private func markSeen() {
        UserDefaults.standard.setBool(true, forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
    }

    private func openShortcutInstallLink() {
        let urlString = UserDefaults.standard.string(forAppKey: AppSettings.Keys.shortcutInstallURL)
            ?? AppSettings.defaultShortcutInstallURL
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Preview

#Preview {
    WiFiShortcutSetupView(
        shortcutsProvider: nil,
        onDismiss: {},
        onSkip: {}
    )
}
