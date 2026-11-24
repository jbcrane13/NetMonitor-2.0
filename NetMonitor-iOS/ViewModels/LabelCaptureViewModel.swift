import CoreGraphics
import Foundation
import NetMonitorCore

/// Reads a device label from a photo and holds the fields while the user reviews them (#456).
/// Nothing is written until ``save(to:among:)``.
@MainActor
@Observable
final class LabelCaptureViewModel {
    enum Phase: Equatable {
        /// Waiting for a photo.
        case choosing
        case reading
        case review
    }

    private(set) var phase: Phase = .choosing
    /// The reading the review started from.
    private(set) var reading: LabelReading?
    /// The fields as the user has edited them.
    var values = LabelValues()

    private let reader: LabelReader

    init(reader: LabelReader = LabelCaptureViewModel.makeReader()) {
        self.reader = reader
    }

    /// The app's reader: Vision OCR and the on-device model, or the UI-test stand-ins.
    static func makeReader() -> LabelReader {
        LabelReader(
            recognizer: LabelServices.recognizer,
            extractor: UITestBootstrap.labelExtractor ?? LabelServices.extractor,
            insight: UITestBootstrap.labelInsightService ?? InsightService.shared
        )
    }

    /// Loads OCR while the user picks a photo; it takes about half a minute cold.
    func prewarm() async {
        await reader.prewarm()
    }

    func read(_ image: CGImage) async {
        phase = .reading
        let reading = await reader.read(image)
        self.reading = reading
        values = LabelValues(reading)
        phase = .review
    }

    /// Back to choosing a photo, dropping the reading and any edits.
    func retake() {
        reading = nil
        values = LabelValues()
        phase = .choosing
    }

    /// Whether `field` shows what the on-device model filled in: it did, and the user
    /// hasn't changed it.
    func isGenerated(_ field: LabelReading.Field) -> Bool {
        guard let reading, reading.generated.contains(field) else { return false }
        return Self.value(field, in: values) == Self.value(field, in: LabelValues(reading))
    }

    /// What Save would do with the MAC on `device`.
    func macOutcome(on device: LocalDevice, among rows: [LocalDevice]) -> LabelCapture.MACOutcome {
        LabelCapture.macOutcome(for: values.mac, on: device, among: rows)
    }

    @discardableResult
    func save(to device: LocalDevice, among rows: [LocalDevice]) -> LabelCapture.MACOutcome {
        LabelCapture.save(values, to: device, among: rows)
    }

    private static func value(_ field: LabelReading.Field, in values: LabelValues) -> String {
        switch field {
        case .maker: values.maker
        case .model: values.model
        case .serial: values.serial
        case .mac: values.mac
        }
    }
}
