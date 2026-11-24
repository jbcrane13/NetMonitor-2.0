import CoreGraphics
import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #456: the label sheet's review state. OCR and the model are stand-ins; devices live in an
/// in-memory store the suite holds for every test.
@Suite("Label capture view model")
@MainActor
struct LabelCaptureViewModelTests {
    private struct Lines: LabelTextRecognizerProtocol {
        let lines: [String]
        func prewarm() async {}
        func recognizeText(in image: CGImage) async -> [String] {
            lines
        }
    }

    private static let labelMAC = "3C:22:FB:0A:1B:2C"
    private static let lines = ["Northwind Networks", "Model: NW-AC1200", "S/N: NW12K4471093", "MAC: \(labelMAC)"]
    private let network = UUID()
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func viewModel(
        model: LabelFields? = nil,
        scanning: Bool = false,
        scan: [DiscoveredDevice] = [],
        device: LocalDevice
    ) -> LabelCaptureViewModel {
        let viewModel = LabelCaptureViewModel(
            reader: LabelReader(
                recognizer: Lines(lines: Self.lines),
                extractor: FixedLabelFieldExtractor(answer: model),
                insight: model == nil ? UnavailableInsightService() : FixedAnswerInsightService(answer: "")
            ),
            isScanning: { scanning },
            liveScan: { scan },
            testImage: { nil }
        )
        viewModel.configure(device: device, context: context)
        return viewModel
    }

    private func row(_ ip: String, mac: String = "") -> LocalDevice {
        let device = LocalDevice(ipAddress: ip, macAddress: mac, networkProfileID: network)
        context.insert(device)
        return device
    }

    private func observed(_ ip: String, mac: String?, name: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: nil,
            discoveredAt: Date(), source: .local, networkProfileID: network
        )
    }

    private static let image: CGImage? = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()

    @Test("Reading a photo opens the review with the fields, model-filled ones marked until edited")
    func reviewMarksGeneratedFields() async throws {
        let viewModel = viewModel(model: LabelFields(status: .found, maker: "Northwind Networks", model: "NW-AC1200"), device: row("192.168.1.10"))
        #expect(viewModel.phase == .choosing)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.phase == .review)
        #expect(viewModel.values == LabelValues(maker: "Northwind Networks", model: "NW-AC1200", serial: "NW12K4471093", mac: Self.labelMAC))
        #expect(viewModel.isGenerated(.model))
        #expect(!viewModel.isGenerated(.mac))
        viewModel.values.model = "NW-AC1200v2"
        #expect(!viewModel.isGenerated(.model))
    }

    @Test("Without the model the review has the code's MAC and serial and no marks")
    func withoutModel() async throws {
        let viewModel = viewModel(device: row("192.168.1.10"))
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.values == LabelValues(serial: "NW12K4471093", mac: Self.labelMAC))
        #expect(LabelReading.Field.allCases.allSatisfy { !viewModel.isGenerated($0) })
    }

    @Test("During a network scan the model isn't asked")
    func noModelDuringScan() async throws {
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"), scanning: true, device: row("192.168.1.10"))
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.values.model.isEmpty)
        #expect(viewModel.values.mac == Self.labelMAC)
        #expect(viewModel.reading?.generated.isEmpty == true)
    }

    @Test("A photo that can't be opened shows an error and goes back to choosing")
    func photoLoadFailure() async {
        let viewModel = viewModel(device: row("192.168.1.10"))
        await viewModel.readPhoto { nil }
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.photoError != nil)
        await viewModel.readPhoto { Data("not an image".utf8) }
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.photoError != nil)
    }

    @Test("Save writes the reviewed values as user-confirmed; Retake drops them")
    func saveAndRetake() async throws {
        let device = row("192.168.1.10")
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"), device: device)
        try await viewModel.read(#require(Self.image))
        #expect(device.modelName == nil, "Reading writes nothing")
        #expect(viewModel.save())
        #expect(device.identity.model == IdentityValue("NW-AC1200", source: .userConfirmed))
        #expect(device.macAddress == Self.labelMAC)
        viewModel.retake()
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.values == LabelValues())
    }

    @Test("Text in the MAC field that isn't a MAC turns Save off")
    func invalidMACBlocksSave() async throws {
        let device = row("192.168.1.10")
        let viewModel = viewModel(device: device)
        try await viewModel.read(#require(Self.image))
        viewModel.values.mac = "3C:22:FB:0A:1B:2"
        #expect(viewModel.macOutcome == .invalid)
        #expect(!viewModel.canSave)
        #expect(!viewModel.save())
        #expect(device.macAddress.isEmpty)
        viewModel.values.mac = ""
        #expect(viewModel.canSave)
    }

    @Test("Use That Device saves to the saved device with the MAC and names it; this device is unchanged")
    func useThatSavedDevice() async throws {
        let current = row("192.168.1.10")
        let other = row("192.168.1.11", mac: Self.labelMAC.lowercased())
        other.customName = "Hall router"
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"), device: current)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.macOutcome == .belongsTo(.saved(other.id)))
        #expect(viewModel.ownerName == "Hall router")
        viewModel.saveToOwner()
        #expect(viewModel.phase == .savedToOther(name: "Hall router"))
        #expect(other.identity.model == IdentityValue("NW-AC1200", source: .userConfirmed))
        #expect(current.modelName == nil)
        #expect(current.macAddress.isEmpty)
    }

    /// Devin's case on #560: the scan shows a MAC-less device at .10 and one at .11 with the
    /// label's MAC; only .10 has a saved row. Saving must not give .10 that MAC, or reloading
    /// the details would hand .10's row to .11.
    @Test("A scanned device without a row owns its MAC; reloading both details keeps them apart")
    func scannedOwnerKeepsRowsApart() async throws {
        let current = row("192.168.1.10")
        current.notes = "Office"
        let scan = [observed("192.168.1.10", mac: nil), observed("192.168.1.11", mac: Self.labelMAC, name: "nas.lan")]
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"), scan: scan, device: current)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.macOutcome == .belongsTo(.scanned(ipAddress: "192.168.1.11")))
        #expect(viewModel.ownerName == "nas.lan")
        #expect(viewModel.save())
        #expect(current.macAddress.isEmpty, "The other device's MAC isn't copied")

        let reloaded = DeviceDetailViewModel.savedRow(
            ipAddress: "192.168.1.10", scanned: scan[0], networkID: network, scan: scan, in: context
        )
        let otherRow = DeviceDetailViewModel.savedRow(
            ipAddress: "192.168.1.11", scanned: scan[1], networkID: network, scan: scan, in: context
        )
        #expect(reloaded.id == current.id)
        #expect(otherRow.id != current.id)
        #expect(otherRow.notes == nil, "The other device doesn't get this device's notes")
    }

    @Test("Use That Device on a scanned device creates its row through the device match")
    func useThatScannedDevice() async throws {
        let current = row("192.168.1.10")
        let scan = [observed("192.168.1.10", mac: nil), observed("192.168.1.11", mac: Self.labelMAC, name: "nas.lan")]
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"), scan: scan, device: current)
        try await viewModel.read(#require(Self.image))
        viewModel.saveToOwner()
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        let created = try #require(rows.first { $0.ipAddress == "192.168.1.11" })
        #expect(created.macAddress == Self.labelMAC)
        #expect(created.identity.model == IdentityValue("NW-AC1200", source: .userConfirmed))
        #expect(viewModel.phase == .savedToOther(name: created.displayName))
        #expect(current.modelName == nil)
    }
}
