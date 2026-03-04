import PhotosUI
import SwiftUI

// MARK: - PhotoLibraryPicker

/// SwiftUI wrapper around PHPickerViewController for selecting floor plan images
/// from the user's photo library. Supports PNG, JPEG, and HEIC formats.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    /// Callback with the selected image data, or nil if cancelled.
    var onImageSelected: (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (Data?) -> Void

        init(onImageSelected: @escaping (Data?) -> Void) {
            self.onImageSelected = onImageSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                onImageSelected(nil)
                return
            }

            let itemProvider = result.itemProvider

            // Try loading as Data to preserve original format (PNG, JPEG, HEIC)
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [onImageSelected] data, _ in
                    Task { @MainActor in
                        onImageSelected(data)
                    }
                }
            } else {
                Task { @MainActor in
                    onImageSelected(nil)
                }
            }
        }
    }
}
