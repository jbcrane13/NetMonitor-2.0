import NetMonitorCore
import SwiftUI
import VisionKit

/// Pair with a Mac (#590): scan the QR code from the Mac's Settings → Companion, or type the code
/// shown under it; then compare the six digits on both screens and confirm on the Mac.
struct PairWithMacView: View {
    @State private var viewModel: PairWithMacViewModel
    @State private var showsScanner = false
    @Environment(\.dismiss) private var dismiss

    /// `mac` is the Mac picked from the list; nil when pairing from a scanned QR alone.
    init(mac: DiscoveredMac?) {
        _viewModel = State(initialValue: PairWithMacViewModel(mac: mac))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .idle, .failed:
                entrySection
            case .connecting:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Connecting to the Mac…")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("pairMac_label_connecting")
                }
                .listRowBackground(Theme.Colors.glassBackground)
            case .comparing(let code, let macName):
                comparingSection(code: code, macName: macName, waiting: false)
            case .waitingForMac(let code, let macName):
                comparingSection(code: code, macName: macName, waiting: true)
            case .paired(let macName):
                pairedSection(macName: macName)
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle(viewModel.mac.map { "Pair with \($0.name)" } ?? "Pair with a Mac")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsScanner) {
            PairingQRScanner { text in
                showsScanner = false
                viewModel.handleScan(text)
            }
        }
        .onAppear { viewModel.appear() }
        .onDisappear { viewModel.disappear() }
        .accessibilityIdentifier("screen_pairWithMac")
    }

    // MARK: - Sections

    @ViewBuilder
    private var entrySection: some View {
        if let inputError = viewModel.inputError {
            Section {
                Label(inputError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("pairMac_label_inputError")
            }
            .listRowBackground(Theme.Colors.glassBackground)
        }
        if case .failed(let message) = viewModel.state {
                Section {
                    Label(message, systemImage: "xmark.octagon")
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityIdentifier("pairMac_label_failed")
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }
            Section {
                Button {
                    showsScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("pairMac_button_scan")
            } footer: {
                Text("On the Mac, open NetMonitor Settings → Companion → Pair iPhone…")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            if viewModel.mac != nil {
                Section {
                    TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-X", text: $viewModel.codeText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("pairMac_textfield_code")
                    GlassButton(title: "Pair", icon: "link", style: .primary, size: .medium, isFullWidth: true) {
                        viewModel.pairWithCode()
                    }
                    .accessibilityIdentifier("pairMac_button_pairWithCode")
                } header: {
                    Text("Or type the code")
                        .foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    Text("Under the QR code, click “Can't scan? Type a code instead”.")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }
    }

    private func comparingSection(code: String, macName: String, waiting: Bool) -> some View {
        Section {
            VStack(spacing: 12) {
                Text("Check that \(macName) shows the same code:")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Text(code)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("pairMac_label_comparisonCode")
                if waiting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Now click Pair on \(macName).")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("pairMac_label_waitingForMac")
                } else {
                    Text("If they match, tap They Match here and click Pair on the Mac. If they differ, tap Don't Match.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    GlassButton(title: "They Match", icon: "checkmark", style: .primary, size: .medium, isFullWidth: true) {
                        viewModel.confirm(true)
                    }
                    .accessibilityIdentifier("pairMac_button_codesMatch")
                    Button("Don't Match", role: .destructive) {
                        viewModel.confirm(false)
                    }
                    .accessibilityIdentifier("pairMac_button_codesDiffer")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Theme.Colors.glassBackground)
    }

    private func pairedSection(macName: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.success)
                Text("Paired with \(macName)")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("pairMac_label_paired")
                GlassButton(title: "Done", icon: "checkmark", style: .primary, size: .medium, isFullWidth: true) {
                    viewModel.done()
                    dismiss()
                }
                .accessibilityIdentifier("pairMac_button_done")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Theme.Colors.glassBackground)
    }
}

/// The camera, reading one NetMonitor QR code. Under `--fake-mac-pairing` it offers the fake Mac's
/// code instead, since the simulator has no camera.
private struct PairingQRScanner: View {
    let onScan: (String) -> Void

    /// The fake Mac's QR under `--fake-mac-pairing`, in Debug builds only.
    private static var testInvitation: CompanionPairingInvitation? {
        #if DEBUG
        UITestFakeMacPairing.invitation
        #else
        nil
        #endif
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let invitation = Self.testInvitation {
                    Button("Scan the test Mac's code") { onScan(invitation.qrText) }
                        .accessibilityIdentifier("pairMac_button_simulateScan")
                } else if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    QRDataScanner(onScan: onScan)
                        .ignoresSafeArea()
                } else {
                    Text("The camera isn't available. Type the code instead.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding()
                }
            }
            .navigationTitle("Scan the Mac's Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("pairMac_button_cancelScan")
                }
            }
        }
    }
}

private struct QRDataScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var delivered = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue, !delivered,
                   text.hasPrefix("netmonitor://pair") {
                    delivered = true
                    dataScanner.stopScanning()
                    onScan(text)
                    return
                }
            }
        }
    }
}
