import SwiftUI
import UniformTypeIdentifiers

// MARK: - DocumentPicker

/// SwiftUI wrapper around UIDocumentPickerViewController for selecting floor plan files.
/// Supports PNG, JPEG, and PDF formats from the Files app and other document providers.
struct DocumentPicker: UIViewControllerRepresentable {
    /// Callback with the selected file URL, or nil if cancelled.
    var onDocumentSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: FloorPlanImporter.documentPickerTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentSelected: onDocumentSelected)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentSelected: (URL) -> Void

        init(onDocumentSelected: @escaping (URL) -> Void) {
            self.onDocumentSelected = onDocumentSelected
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            Task { @MainActor in
                onDocumentSelected(url)
            }
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            // No action needed — sheet dismisses automatically
        }
    }
}
