import CoreGraphics
import Foundation
import NetMonitorCore
import UIKit

/// Reads a modem's status lights from a photo (#558). The on-device model only reads each light's
/// label and colour; every line shown is the app's own text (`ModemPanelReport`). The photo stays
/// in memory on this iPhone and is dropped after the reading; nothing is saved. A reading goes to
/// `onReading`, which hands it to the Troubleshoot session's findings (#625).
@MainActor
@Observable
final class ModemLightsViewModel: PhotoReading {
    enum Phase: Equatable {
        /// Waiting for a photo.
        case choosing
        /// Loading the chosen photo.
        case loading
        case reading
        case result(ModemPanelReport)
        /// The model said the photo isn't a modem's lights, or read none.
        case notAPanel
    }

    private(set) var phase: Phase = .choosing
    /// Why the last photo couldn't be read, until another is chosen.
    private(set) var errorMessage: String?

    private let extractor: any ModemLightExtractorProtocol
    private let isScanning: @MainActor () -> Bool
    private let testImage: @MainActor () -> CGImage?
    private let onReading: @MainActor (ModemPanelReport) -> Void
    /// The photo being read; cancelled when the sheet closes or another photo is chosen.
    private var task: Task<Void, Never>?

    init(
        extractor: any ModemLightExtractorProtocol = ModemLightsViewModel.extractor,
        isScanning: @escaping @MainActor () -> Bool = { DeviceDiscoveryService.shared.isScanning },
        testImage: @escaping @MainActor () -> CGImage? = { UITestBootstrap.usesTestModemImage ? UITestBootstrap.testModemImage() : nil },
        onReading: @escaping @MainActor (ModemPanelReport) -> Void = { _ in }
    ) {
        self.extractor = extractor
        self.isScanning = isScanning
        self.testImage = testImage
        self.onReading = onReading
    }

    /// The app's reader, or the UI-test stand-in.
    static var extractor: any ModemLightExtractorProtocol {
        UITestBootstrap.modemLightExtractor ?? ModemLightServices.extractor
    }

    /// Whether to offer the reader: this iPhone's own model must see images. A paired Mac
    /// doesn't count; the photo never leaves the device.
    static var isAvailable: Bool {
        extractor.isAvailable
    }

    /// Under `UITEST_MODEM_IMAGE` the drawn test panel is read at once.
    func start() async {
        if let image = testImage() {
            await read(image)
        }
    }

    // MARK: - Reading

    /// Reads a photo from the library in the background.
    @discardableResult
    func choosePhoto(_ load: @escaping @Sendable () async -> Data?) -> Task<Void, Never> {
        run { await $0.readPhoto(load) }
    }

    /// Reads a photo from the camera in the background.
    @discardableResult
    func takePhoto(_ photo: UIImage) -> Task<Void, Never> {
        run { await $0.readCameraPhoto(photo) }
    }

    /// Stops the reading in progress, when the sheet closes: the model stops, and the photo is
    /// released.
    func cancel() {
        task?.cancel()
        task = nil
    }

    private func run(_ work: @escaping @MainActor (ModemLightsViewModel) async -> Void) -> Task<Void, Never> {
        task?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await work(self)
        }
        self.task = task
        return task
    }

    func photoLoading() {
        errorMessage = nil
        phase = .loading
    }

    func photoFailed(_ message: String) {
        errorMessage = message
        phase = .choosing
    }

    /// Reads `image`. The model is never asked during a network scan (#447), and without it
    /// nothing can be read, so the user waits for the scan.
    func read(_ image: CGImage) async {
        guard !isScanning() else {
            photoFailed("A network scan is running. Try again when it finishes.")
            return
        }
        errorMessage = nil
        phase = .reading
        let answer = await extractor.readLights(in: image)
        // Closed meanwhile: nothing more is shown.
        guard !Task.isCancelled else { return }
        guard let answer else {
            photoFailed("The lights couldn't be read. Try another photo.")
            return
        }
        let report = ModemPanelReport(answer: answer)
        phase = report.isPanel ? .result(report) : .notAPanel
        if report.isPanel {
            onReading(report)
        }
    }

    /// Back to choosing a photo, dropping the reading.
    func retake() {
        cancel()
        phase = .choosing
        errorMessage = nil
    }
}
