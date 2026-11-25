import CoreImage.CIFilterBuiltins
import NetMonitorCore
import SwiftUI

/// Pair iPhone… (#590): a one-time QR code and typed code, then the comparison code to confirm.
struct CompanionPairingSheet: View {
    let model: CompanionSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsCode = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair an iPhone")
                .font(.title2.bold())

            if let pending = model.pending {
                confirmation(pending)
            } else if let outcome = model.outcome {
                outcomeView(outcome)
            } else if let offer = model.offer {
                invitation(offer)
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .frame(width: 380)
        .task { await model.openPairing() }
        .onDisappear {
            Task { await model.closePairing() }
        }
    }

    private func invitation(_ offer: CompanionPairingOffer) -> some View {
        VStack(spacing: 12) {
            Text("On your iPhone, open NetMonitor → Settings → Mac Companion → Pair with QR Code.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let image = Self.qrImage(offer.invitation.qrText) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .accessibilityLabel("Pairing QR code")
                    .accessibilityIdentifier("pairing_image_qr")
            }
            DisclosureGroup("Can't scan? Type a code instead", isExpanded: $showsCode) {
                Text(offer.code.display)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pairing_label_code")
            }
            .accessibilityIdentifier("pairing_toggle_showCode")
            Text(timerInterval: Date()...offer.expiresAt, countsDown: true)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("The code works once and expires in ten minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("pairing_button_cancel")
        }
    }

    private func confirmation(_ pending: CompanionSettingsViewModel.PendingConfirmation) -> some View {
        VStack(spacing: 12) {
            Text("“\(pending.phoneName)” wants to pair.")
            Text("Check that the iPhone shows the same code:")
                .foregroundStyle(.secondary)
            Text(pending.code)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .accessibilityIdentifier("pairing_label_comparisonCode")
            Text("If the codes differ, click Don't Pair: another device may be in the middle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Don't Pair") {
                    Task { await model.confirm(false) }
                }
                .accessibilityIdentifier("pairing_button_reject")
                Button("Pair") {
                    Task { await model.confirm(true) }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("pairing_button_confirm")
            }
        }
    }

    private func outcomeView(_ outcome: CompanionSettingsViewModel.PairingOutcome) -> some View {
        VStack(spacing: 12) {
            switch outcome {
            case .paired(let name):
                Label("Paired with \(name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("pairing_label_paired")
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("pairing_label_failed")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("pairing_button_done")
        }
    }

    private static func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
