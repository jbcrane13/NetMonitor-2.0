import NetMonitorCore
import os
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Reads a device's label from a photo and lets the user review the fields before saving
/// them to the device (#456). Nothing is saved without Save.
struct LabelCaptureView: View {
    let device: LocalDevice
    /// Called after a save, with the device the fields were written to.
    var onSaved: (LocalDevice) -> Void

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
                case .reading: readingView
                case .review: review
                }
            }
            .navigationTitle("Scan Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("labelCapture_button_cancel")
                }
                if viewModel.phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(to: device) }
                            .accessibilityIdentifier("labelCapture_button_save")
                    }
                }
            }
        }
        .task {
            await viewModel.prewarm()
        }
        .task {
            if UITestBootstrap.usesTestLabelImage, let image = UITestBootstrap.testLabelImage() {
                await viewModel.read(image)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await read(image)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCapture { image in
                showsCamera = false
                Task { await read(image) }
            } onCancel: {
                showsCamera = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Choosing a photo

    private var chooser: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Take or choose a photo of the label on the device. The text is read on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("labelCapture_label_instructions")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("labelCapture_button_camera")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("labelCapture_button_photoLibrary")
        }
        .padding(24)
    }

    private var readingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading the label…")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("labelCapture_label_reading")
    }

    // MARK: - Review

    private var review: some View {
        let rows = savedRows()
        return Form {
            if viewModel.reading?.isLabel == false {
                Section {
                    Text("This doesn't look like a device label. You can still type the details.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("labelCapture_label_notALabel")
                }
            } else if viewModel.reading?.isEmpty == true {
                Section {
                    Text("No details were found on the label. You can type them.")
                        .foregroundStyle(.secondary)
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
            macSection(rows: rows)
            Section {
                Button("Retake Photo") { viewModel.retake() }
                    .accessibilityIdentifier("labelCapture_button_retake")
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, field: LabelReading.Field, id: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
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
    private func macSection(rows: [LocalDevice]) -> some View {
        switch viewModel.macOutcome(on: device, among: rows) {
        case let .belongsTo(id):
            if let owner = rows.first(where: { $0.id == id }) {
                Section {
                    Text("\(owner.displayName) already has this MAC address, so it isn't copied to this device.")
                        .accessibilityIdentifier("labelCapture_label_macConflict")
                    Button("Use That Device") { save(to: owner) }
                        .accessibilityIdentifier("labelCapture_button_useOtherDevice")
                }
            }
        case let .kept(existing):
            Section {
                Text("This device keeps the MAC address the network reports (\(existing)).")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("labelCapture_label_macKept")
            }
        case .none, .unchanged, .written:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func read(_ image: UIImage) async {
        guard let cgImage = LabelPhoto.upright(image) else { return }
        await viewModel.read(cgImage)
    }

    private func save(to target: LocalDevice) {
        viewModel.save(to: target, among: savedRows())
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Label capture save failed: \(error.localizedDescription, privacy: .public)")
        }
        onSaved(target)
        dismiss()
    }

    private func savedRows() -> [LocalDevice] {
        (try? modelContext.fetch(FetchDescriptor<LocalDevice>())) ?? []
    }
}

// MARK: - Photo input

/// Photos as Vision should see them: upright, and no larger than it needs.
enum LabelPhoto {
    static let maxDimension: CGFloat = 2048

    static func upright(_ image: UIImage) -> CGImage? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

/// The system camera, for one photo of a label.
struct CameraCapture: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
