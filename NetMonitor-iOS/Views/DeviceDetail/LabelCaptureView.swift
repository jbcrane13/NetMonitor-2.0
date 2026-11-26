import NetMonitorCore
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Reads a device's label from a photo and lets the user review the fields before saving
/// them to the device (#456). Nothing is saved without Save or Use That Device.
struct LabelCaptureView: View {
    /// The device's primary row; its maker, model and serial are saved here (#594).
    let device: LocalDevice
    /// The interface a new MAC is written to: the device's current member, when it has several.
    var current: LocalDevice?
    /// Called after a save, so device detail shows what changed.
    var onSaved: () -> Void

    @State private var viewModel = LabelCaptureViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .choosing: chooser
                case .loading: progress("Opening the photo…", id: "labelCapture_label_loading")
                case .reading: progress("Reading the label…", id: "labelCapture_label_reading")
                case .review: review
                case let .savedToOther(name): savedToOther(name)
                }
            }
            .scrollContentBackground(.hidden)
            .themedBackground()
            .navigationTitle("Scan Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar { toolbar }
        }
        .task {
            viewModel.configure(device: device, current: current, context: modelContext)
            await viewModel.start()
        }
        .photoIntake(photoItem: $photoItem, showsCamera: $showsCamera) { load in
            Task { await viewModel.readPhoto(load) }
        } onCamera: { image in
            Task { await viewModel.readCameraPhoto(image) }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { viewModel.saveError != nil },
            set: {
                if !$0 {
                    viewModel.dismissSaveError()
                }
            }
        )) {
            Button("OK") { viewModel.dismissSaveError() }
        } message: {
            Text(viewModel.saveError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if case .savedToOther = viewModel.phase {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("labelCapture_button_done")
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("labelCapture_button_cancel")
            }
            if viewModel.phase == .review {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("labelCapture_button_save")
                }
            }
        }
    }

    // MARK: - Choosing a photo

    private var chooser: some View {
        PhotoChooser(
            screen: "labelCapture",
            systemImage: "text.viewfinder",
            instructions: "Take or choose a photo of the label on the device. The text is read on this device.",
            error: viewModel.photoError,
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

    // MARK: - Review

    private var review: some View {
        Form {
            if viewModel.reading?.isLabel == false {
                Section {
                    Text("This doesn't look like a device label. You can still type the details.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("labelCapture_label_notALabel")
                }
            } else if viewModel.reading?.isEmpty == true {
                Section {
                    Text("No details were found on the label. You can type them.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("labelCapture_label_nothingFound")
                }
            }
            Section {
                field("Maker", text: $viewModel.values.maker, field: .maker, id: "labelCapture_field_maker")
                field("Model", text: $viewModel.values.model, field: .model, id: "labelCapture_field_model")
                field("Serial number", text: $viewModel.values.serial, field: .serial, id: "labelCapture_field_serial")
                field("MAC address", text: $viewModel.values.mac, field: .mac, id: "labelCapture_field_mac")
            } footer: {
                if viewModel.reading?.generated.isEmpty == false {
                    Label("Marked fields were read by the on-device model. Check them against the label.", systemImage: "sparkles")
                        .accessibilityIdentifier("labelCapture_label_generatedNote")
                }
            }
            macSection
            Section {
                Button("Retake Photo") { viewModel.retake() }
                    .accessibilityIdentifier("labelCapture_button_retake")
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, field: LabelReading.Field, id: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 110, alignment: .leading)
            TextField(title, text: text)
                .textInputAutocapitalization(field == .maker ? .words : .characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier(id)
            if viewModel.isGenerated(field) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityLabel("Read by the on-device model")
                    .accessibilityIdentifier("\(id)_generated")
            }
        }
    }

    @ViewBuilder
    private var macSection: some View {
        switch viewModel.macOutcome {
        case .belongsTo:
            Section {
                Text("\(viewModel.ownerName ?? "Another device") already has this MAC address, so it isn't copied to this device. "
                    + "Use That Device saves these details to it instead.")
                    .accessibilityIdentifier("labelCapture_label_macConflict")
                Button("Use That Device") { viewModel.saveToOwner() }
                    .accessibilityIdentifier("labelCapture_button_useOtherDevice")
            }
        case let .kept(existing):
            Section {
                Text("This device keeps the MAC address the network reports (\(existing)).")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("labelCapture_label_macKept")
            }
        case .invalid:
            Section {
                Text("That isn't a MAC address. Use six pairs like 3C:22:FB:0A:1B:2C, or clear the field.")
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("labelCapture_label_macInvalid")
            }
        case .none, .unchanged, .written:
            EmptyView()
        }
    }

    private func savedToOther(_ name: String) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.success)
            Text("Saved to \(name)")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("labelCapture_label_savedToOther")
            Text("This device wasn't changed.")
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Layout.screenPadding)
    }
}
