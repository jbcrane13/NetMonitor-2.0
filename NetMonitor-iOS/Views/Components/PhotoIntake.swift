import PhotosUI
import SwiftUI
import UIKit

/// Take or choose a photo: the chooser shared by label capture (#456) and modem lights (#558).
/// Identifiers are `{screen}_button_camera`, `{screen}_button_photoLibrary`,
/// `{screen}_label_instructions` and `{screen}_label_photoError`.
struct PhotoChooser: View {
    /// Accessibility prefix, such as "labelCapture".
    let screen: String
    let systemImage: String
    let instructions: String
    /// Why the last photo couldn't be read, if it couldn't.
    let error: String?
    @Binding var photoItem: PhotosPickerItem?
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text(instructions)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("\(screen)_label_instructions")
            if let error {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityIdentifier("\(screen)_label_photoError")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(action: onTakePhoto) {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("\(screen)_button_camera")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("\(screen)_button_photoLibrary")
        }
        .tint(Theme.Colors.accent)
        .padding(Theme.Layout.screenPadding)
    }
}

extension View {
    /// Hands a chosen photo's loader, or a camera photo, to the reader: the Photos selection is
    /// cleared at once, and the camera is a full-screen cover while `showsCamera` is true.
    func photoIntake(
        photoItem: Binding<PhotosPickerItem?>,
        showsCamera: Binding<Bool>,
        onPhoto: @escaping (@escaping @Sendable () async -> Data?) -> Void,
        onCamera: @escaping (UIImage) -> Void
    ) -> some View {
        onChange(of: photoItem.wrappedValue) { _, item in
            guard let item else { return }
            photoItem.wrappedValue = nil
            onPhoto { try? await item.loadTransferable(type: Data.self) }
        }
        .fullScreenCover(isPresented: showsCamera) {
            CameraCapture { image in
                showsCamera.wrappedValue = false
                onCamera(image)
            } onCancel: {
                showsCamera.wrappedValue = false
            }
            .ignoresSafeArea()
        }
    }
}

/// The system camera, for one photo.
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
