import NetMonitorCore
import PhotosUI
import SwiftUI
import UIKit

/// Reads a modem's status lights from a photo (#558), opened from Troubleshoot. Each light is
/// shown as read with the app's meaning; the on-device model only words those meanings.
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await viewModel.readPhoto { try? await item.loadTransferable(type: Data.self) } }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCapture { image in
                showsCamera = false
                Task { await viewModel.readCameraPhoto(image) }
            } onCancel: {
                showsCamera = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Choosing a photo

    private var chooser: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text("Take or choose a photo of the front of your modem or router, with its lights in view. "
                + "The photo is read on this iPhone and isn't saved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("modemLights_label_instructions")
            if let error = viewModel.photoError {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("modemLights_label_photoError")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("modemLights_button_camera")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("modemLights_button_photoLibrary")
        }
        .tint(Theme.Colors.accent)
        .padding(Theme.Layout.screenPadding)
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
                    ForEach(report.verdicts) { verdict in
                        lightRow(verdict)
                    }
                    Label(ModemPanelReport.blinkingNote + ". A blinking light can mean the modem is busy or still starting.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("modemLights_label_blinking")
                }
                .glassCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("modemLights_list_lights")
                wordingSection
                Button("Retake Photo") { viewModel.retake() }
                    .tint(Theme.Colors.accent)
                    .accessibilityIdentifier("modemLights_button_retake")
            }
            .padding(Theme.Layout.screenPadding)
        }
    }

    private func lightRow(_ verdict: ModemLightVerdict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(swatch(verdict.color))
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
                    .foregroundStyle(tone(verdict.meaning?.severity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modemLights_row_\(verdict.id)")
    }

    private func swatch(_ color: ModemLightColor) -> Color {
        switch color {
        case .green: .green
        case .amber: .orange
        case .red: .red
        case .blue: .blue
        case .white: .white
        case .off, .unknown: .clear
        }
    }

    private func tone(_ severity: ModemLightSeverity?) -> Color {
        switch severity {
        case .problem: Theme.Colors.error
        case .attention: Theme.Colors.warning
        default: Theme.Colors.textSecondary
        }
    }

    @ViewBuilder
    private var wordingSection: some View {
        switch viewModel.wording {
        case .none:
            EmptyView()
        case .writing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Writing an explanation…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("modemLights_label_writing")
        case let .written(text):
            VStack(alignment: .leading, spacing: 8) {
                Label("Explanation", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("modemLights_label_explanation")
                Text("Written by the on-device model from the lights above. Check it against them.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("modemLights_label_generated")
            }
            .glassCard()
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
