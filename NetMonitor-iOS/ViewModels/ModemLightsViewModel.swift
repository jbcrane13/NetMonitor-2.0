import CoreGraphics
import Foundation
import NetMonitorCore
import UIKit

/// Reads a modem's status lights from a photo (#558): the on-device model names each light's
/// label and colour, the app says what they mean (`ModemPanelReport`), and the model may then
/// word the app's meanings. The photo stays in memory on this iPhone and is dropped after the
/// reading; nothing is saved.
@MainActor
@Observable
final class ModemLightsViewModel {
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

    /// The model's wording of the app's meanings, under the result.
    enum Wording: Equatable {
        case none
        case writing
        case written(String)
    }

    private(set) var phase: Phase = .choosing
    private(set) var wording: Wording = .none
    /// Why the last photo couldn't be read, until another is chosen.
    private(set) var photoError: String?

    private let extractor: any ModemLightExtractorProtocol
    private let insight: any InsightServiceProtocol
    private let isScanning: @MainActor () -> Bool
    private let testImage: @MainActor () -> CGImage?

    init(
        extractor: any ModemLightExtractorProtocol = ModemLightsViewModel.extractor,
        insight: any InsightServiceProtocol = UITestBootstrap.modemLightsInsightService ?? InsightService.shared,
        isScanning: @escaping @MainActor () -> Bool = { DeviceDiscoveryService.shared.isScanning },
        testImage: @escaping @MainActor () -> CGImage? = { UITestBootstrap.usesTestModemImage ? UITestBootstrap.testModemImage() : nil }
    ) {
        self.extractor = extractor
        self.insight = insight
        self.isScanning = isScanning
        self.testImage = testImage
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

    /// Reads a photo from the library; `load` returns its data, or nil when Photos can't.
    func readPhoto(_ load: @Sendable () async -> Data?) async {
        photoError = nil
        phase = .loading
        guard let data = await load(), let image = await LabelPhoto.upright(data: data) else {
            fail("That photo couldn't be opened. Try another one.")
            return
        }
        await read(image)
    }

    /// Reads a photo from the camera.
    func readCameraPhoto(_ photo: UIImage) async {
        photoError = nil
        phase = .loading
        guard let image = await LabelPhoto.upright(photo) else {
            fail("That photo couldn't be opened. Try again.")
            return
        }
        await read(image)
    }

    /// Reads `image`, then asks for the wording. The model is never asked during a network scan
    /// (#447), and without it nothing can be read, so the user waits for the scan.
    func read(_ image: CGImage) async {
        guard !isScanning() else {
            fail("A network scan is running. Try again when it finishes.")
            return
        }
        photoError = nil
        wording = .none
        phase = .reading
        guard let answer = await extractor.readLights(in: image) else {
            fail("The lights couldn't be read. Try another photo.")
            return
        }
        let report = ModemPanelReport(answer: answer)
        guard report.isPanel else {
            phase = .notAPanel
            return
        }
        phase = .result(report)
        await word(report)
    }

    /// The model words the app's meanings; the app's own lines are already on screen and stay
    /// whatever it answers. An answer that fails `InsightSummarizer`'s checks isn't shown.
    private func word(_ report: ModemPanelReport) async {
        guard let request = report.insightRequest, !report.keyPoints.isEmpty, insight.isAvailable, !isScanning() else { return }
        wording = .writing
        let answer = await InsightSummarizer.summary(for: request, service: insight, timeout: .seconds(20))
        // Retaken meanwhile: this answer belongs to another photo.
        guard phase == .result(report) else { return }
        wording = answer.map(Wording.written) ?? .none
    }

    /// Back to choosing a photo, dropping the reading.
    func retake() {
        phase = .choosing
        wording = .none
        photoError = nil
    }

    private func fail(_ message: String) {
        photoError = message
        phase = .choosing
    }
}
