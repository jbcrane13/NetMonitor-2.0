import NetMonitorCore
import PhotosUI
import SwiftUI

/// Reads a modem's status lights from a photo (#558), opened from Troubleshoot. Each light is
/// shown as read with the app's meaning; the on-device model only reads labels and colours, and
/// writes nothing the user sees.
struct ModemLightsView: View {
    @State private var viewModel = ModemLightsViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .choosing: chooser
                case .loading: progress("Opening the photo…", id: "modemLights_label_loading")
                case .reading: progress("Reading the lights…", id: "modemLights_label_reading")
                case let .result(report): result(report)
                case .notAPanel: notAPanel
                }
            }
            .themedBackground()
            .navigationTitle("Modem Lights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("modemLights_button_done")
                }
            }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .photoIntake(photoItem: $photoItem, showsCamera: $showsCamera) { load in
            viewModel.choosePhoto(load)
        } onCamera: { image in
            viewModel.takePhoto(image)
        }
    }

    // MARK: - Choosing a photo

    private var chooser: some View {
        PhotoChooser(
            screen: "modemLights",
            systemImage: "camera.viewfinder",
            instructions: "Take or choose a photo of the front of your modem or router, with its lights in view. "
                + "The photo is read on this iPhone and isn't saved.",
            error: viewModel.errorMessage,
            photoItem: $photoItem
        ) {
            showsCamera = true
        }
    }

    private func progress(_ text: String, id: String) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            ProgressView()
                .tint(Theme.Colors.accent)
            Text(text)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier(id)
        }
    }

    // MARK: - Result

    private func result(_ report: ModemPanelReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.headline)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("modemLights_label_headline")
                    ForEach(Array(report.notices.enumerated()), id: \.offset) { index, notice in
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("modemLights_label_notice_\(index)")
                    }
                    ForEach(report.verdicts) { verdict in
                        lightRow(verdict)
                    }
                    caption(ModemPanelReport.blinkingNote + ". A blinking light can mean the modem is busy or still starting.",
                            systemImage: "info.circle", id: "modemLights_label_blinking")
                    caption(ModemPanelReport.whiteLightNote, systemImage: "lightbulb", id: "modemLights_label_whiteNote")
                }
                .glassCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("modemLights_list_lights")
                Button("Retake Photo") { viewModel.retake() }
                    .tint(Theme.Colors.accent)
                    .accessibilityIdentifier("modemLights_button_retake")
            }
            .padding(Theme.Layout.screenPadding)
        }
    }

    private func caption(_ text: String, systemImage: String, id: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }

    /// One light: its colour as read, then the app's meaning. The meaning's weight shows as an icon
    /// with a spoken name as well as a colour, so it doesn't rest on colour alone.
    private func lightRow(_ verdict: ModemLightVerdict) -> some View {
        let tone = Tone(verdict.meaning?.severity)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(swatch(verdict.note == nil ? verdict.color : .unknown))
                .overlay(Circle().stroke(Theme.Colors.textTertiary, lineWidth: 1))
                .frame(width: 14, height: 14)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.reading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(verdict.meaning?.text ?? verdict.note ?? "The app doesn't know what this light means.")
                    .font(.caption)
                    .foregroundStyle(tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
                .accessibilityLabel(tone.name)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modemLights_row_\(verdict.id)")
    }

    /// How a meaning's weight is shown: icon, spoken name and colour together.
    private struct Tone {
        let symbol: String
        let name: String
        let color: Color

        init(_ severity: ModemLightSeverity?) {
            switch severity {
            case .problem: (symbol, name, color) = ("exclamationmark.octagon.fill", "Problem", Theme.Colors.error)
            case .attention: (symbol, name, color) = ("exclamationmark.triangle.fill", "Check", Theme.Colors.warning)
            case .note: (symbol, name, color) = ("info.circle", "Note", Theme.Colors.textSecondary)
            case .normal: (symbol, name, color) = ("checkmark.circle", "Normal", Theme.Colors.textSecondary)
            case nil: (symbol, name, color) = ("questionmark.circle", "Not judged", Theme.Colors.textSecondary)
            }
        }
    }

    private func swatch(_ color: ModemLightColor) -> Color {
        switch color {
        case .green: .green
        case .amber: .orange
        case .red: .red
        case .blue: .blue
        case .white: .white
        case .purple: .purple
        case .off, .unknown: .clear
        }
    }

    private var notAPanel: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Text("This doesn't look like a modem's status lights. Try a photo of the front, with the lights in view.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("modemLights_label_notAPanel")
            Button("Retake Photo") { viewModel.retake() }
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("modemLights_button_retake")
        }
        .padding(Theme.Layout.screenPadding)
    }
}
