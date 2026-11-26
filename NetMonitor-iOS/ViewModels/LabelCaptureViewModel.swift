import CoreGraphics
import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import UIKit

/// Reads a device label from a photo and holds the fields while the user reviews them (#456).
/// Nothing is written until ``save()`` or ``saveToOwner()``.
@MainActor
@Observable
final class LabelCaptureViewModel {
    enum Phase: Equatable {
        /// Waiting for a photo.
        case choosing
        /// Loading the chosen photo.
        case loading
        case reading
        case review
        /// "Use That Device" saved the fields to another device, named here.
        case savedToOther(name: String)
    }

    private(set) var phase: Phase = .choosing
    /// The reading the review started from.
    private(set) var reading: LabelReading?
    /// The fields as the user has edited them; the only state the sheet writes.
    var values = LabelValues()
    /// Why the last photo couldn't be read, until another is chosen.
    private(set) var photoError: String?
    /// Why the last save failed; the review stays open.
    private(set) var saveError: String?

    private let reader: LabelReader
    private let isScanning: @MainActor () -> Bool
    private let liveScan: @MainActor () -> [DiscoveredDevice]
    private let testImage: @MainActor () -> CGImage?
    /// The device's primary row (#594): the maker, model and serial are written here.
    private var device: LocalDevice?
    /// The interface the MAC is written to: the device's current member, or the device itself.
    private var macTarget: LocalDevice?
    private var context: ModelContext?

    init(
        reader: LabelReader = LabelCaptureViewModel.makeReader(),
        isScanning: @escaping @MainActor () -> Bool = { DeviceDiscoveryService.shared.isScanning },
        liveScan: @escaping @MainActor () -> [DiscoveredDevice] = { DeviceDetailViewModel.liveScan() },
        testImage: @escaping @MainActor () -> CGImage? = { UITestBootstrap.usesTestLabelImage ? UITestBootstrap.testLabelImage() : nil }
    ) {
        self.reader = reader
        self.isScanning = isScanning
        self.liveScan = liveScan
        self.testImage = testImage
    }

    /// The app's reader: Vision OCR and the on-device model, or the UI-test stand-ins.
    static func makeReader() -> LabelReader {
        LabelReader(
            recognizer: LabelServices.recognizer,
            extractor: UITestBootstrap.labelExtractor ?? LabelServices.extractor,
            insight: UITestBootstrap.labelInsightService ?? InsightService.shared
        )
    }

    /// The device the label belongs to, and the store its fields are saved in. For a device of
    /// several interfaces (#594), `device` is its primary and `current` the member the MAC is
    /// written to.
    func configure(device: LocalDevice, current: LocalDevice? = nil, context: ModelContext) {
        self.device = device
        macTarget = current ?? device
        self.context = context
    }

    /// Loads OCR while the user picks a photo; it takes about half a minute cold. Under
    /// `UITEST_LABEL_IMAGE` the drawn test label is read at once.
    func start() async {
        if let image = testImage() {
            async let warm: Void = reader.prewarm()
            await read(image)
            await warm
        } else {
            await reader.prewarm()
        }
    }

    // MARK: - Reading

    /// Reads a photo from the library; `load` returns its data, or nil when Photos can't.
    func readPhoto(_ load: @Sendable () async -> Data?) async {
        photoError = nil
        phase = .loading
        guard let data = await load(), let image = await LabelPhoto.upright(data: data) else {
            photoError = "That photo couldn't be opened. Try another one."
            phase = .choosing
            return
        }
        await read(image)
    }

    /// Reads a photo from the camera.
    func readCameraPhoto(_ photo: UIImage) async {
        photoError = nil
        phase = .loading
        guard let image = await LabelPhoto.upright(photo) else {
            photoError = "That photo couldn't be opened. Try again."
            phase = .choosing
            return
        }
        await read(image)
    }

    /// Reads `image`. While a network scan runs the model isn't asked (#447); the app's own
    /// reading of the MAC and serial is used.
    func read(_ image: CGImage) async {
        phase = .reading
        let reading = await reader.read(image, allowModel: !isScanning())
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

    // MARK: - MAC

    /// What Save would do with the MAC, checked against the saved devices and the latest scan.
    /// Another interface of the same device having it isn't another device's MAC (#594).
    var macOutcome: LabelCapture.MACOutcome {
        guard let device, let macTarget else { return .none }
        let rows = savedRows()
        let outcome = LabelCapture.macOutcome(for: values.mac, on: macTarget, among: rows, scanned: scan(for: macTarget))
        guard case let .belongsTo(owner) = outcome else { return outcome }
        let members = DeviceGroupResolver(rows: rows).device(for: device.id)?.members ?? [device]
        switch owner {
        case let .saved(id) where members.contains { $0.id == id }:
            return .unchanged
        case let .scanned(ipAddress) where members.contains { $0.ipAddress == ipAddress }:
            return .unchanged
        default:
            return outcome
        }
    }

    /// Save is off while the MAC field holds text that isn't a MAC.
    var canSave: Bool {
        phase == .review && macOutcome != .invalid
    }

    /// The name of the other device that has the MAC, for the review to show.
    var ownerName: String? {
        guard case let .belongsTo(owner) = macOutcome, let device else { return nil }
        switch owner {
        case let .saved(id): return DeviceGroupResolver(rows: savedRows()).device(for: id)?.displayName
        case let .scanned(ipAddress):
            let found = scan(for: device).first { $0.ipAddress == ipAddress }
            return found?.hostname ?? ipAddress
        }
    }

    // MARK: - Saving

    /// Saves the reviewed fields to the device: the maker, model and serial to its primary, the
    /// MAC (when it is written) to the current member only (#594). Returns whether the sheet can
    /// close.
    func save() -> Bool {
        guard canSave, let device, let macTarget else { return false }
        let rows = savedRows()
        var identity = values
        identity.mac = ""
        LabelCapture.save(identity, to: device, among: rows, scanned: scan(for: device))
        if macOutcome == .written {
            LabelCapture.save(LabelValues(mac: values.mac), to: macTarget, among: rows, scanned: scan(for: macTarget))
        }
        return persist()
    }

    /// "Use That Device": saves the reviewed fields to the device that has the MAC, creating
    /// its saved row through the device match if the scan saw it but it has none yet. The
    /// review then names the device it updated.
    func saveToOwner() {
        guard case let .belongsTo(owner) = macOutcome, let device, let context else { return }
        let target: LocalDevice?
        switch owner {
        case let .saved(id):
            // The owner's device, whichever interface has the MAC: its primary takes the fields.
            target = DeviceGroupResolver(rows: savedRows()).device(for: id)?.primary
        case let .scanned(ipAddress):
            let network = scan(for: device)
            target = network.first { $0.ipAddress == ipAddress }.map { observed in
                DeviceDetailViewModel.savedRow(
                    ipAddress: ipAddress, scanned: observed, macAddress: observed.macAddress,
                    networkID: device.networkProfileID, scan: network, in: context
                )
            }
        }
        guard let target else { return }
        LabelCapture.save(values, to: target, among: savedRows(), scanned: scan(for: target))
        if persist() {
            phase = .savedToOther(name: DeviceGroupResolver(rows: savedRows()).device(for: target.id)?.displayName ?? target.displayName)
        }
    }

    func dismissSaveError() {
        saveError = nil
    }

    private func persist() -> Bool {
        do {
            try context?.save()
            return true
        } catch {
            saveError = "The details couldn't be saved. Try again."
            return false
        }
    }

    private func savedRows() -> [LocalDevice] {
        (try? context?.fetch(FetchDescriptor<LocalDevice>())) ?? []
    }

    /// The latest scan's devices on `device`'s network, as device detail matches against.
    private func scan(for device: LocalDevice) -> [DiscoveredDevice] {
        liveScan().filter { $0.networkProfileID == device.networkProfileID }
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

// MARK: - Photo input

/// Photos as Vision should see them: upright, and no larger than it needs. Drawn off the
/// main actor; a 12-megapixel photo takes a moment.
enum LabelPhoto {
    static let maxDimension: CGFloat = 2048

    static func upright(data: Data) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data).flatMap(draw)
        }.value
    }

    static func upright(_ image: UIImage) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            draw(image)
        }.value
    }

    nonisolated private static func draw(_ image: UIImage) -> CGImage? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
