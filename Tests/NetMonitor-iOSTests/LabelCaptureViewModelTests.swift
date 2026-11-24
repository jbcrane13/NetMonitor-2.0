import CoreGraphics
import Foundation
import NetMonitorCore
import NetworkScanKit
import Testing
@testable import NetMonitor_iOS

/// #456: the label sheet's review state. OCR and the model are stand-ins.
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

    private func viewModel(model: LabelFields?) -> LabelCaptureViewModel {
        LabelCaptureViewModel(reader: LabelReader(
            recognizer: Lines(lines: ["Northwind Networks", "Model: NW-AC1200", "S/N: NW12K4471093", "MAC: 00:1E:42:7A:9C:31"]),
            extractor: FixedLabelFieldExtractor(answer: model),
            insight: model == nil ? UnavailableInsightService() : FixedAnswerInsightService(answer: "")
        ))
    }

    private static let image: CGImage? = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()

    @Test("Reading a photo opens the review with the fields, model-filled ones marked until edited")
    func reviewMarksGeneratedFields() async throws {
        let viewModel = viewModel(model: LabelFields(status: .found, maker: "Northwind Networks", model: "NW-AC1200"))
        #expect(viewModel.phase == .choosing)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.phase == .review)
        #expect(viewModel.values == LabelValues(maker: "Northwind Networks", model: "NW-AC1200", serial: "NW12K4471093", mac: "00:1E:42:7A:9C:31"))
        #expect(viewModel.isGenerated(.model))
        #expect(!viewModel.isGenerated(.mac))
        viewModel.values.model = "NW-AC1200v2"
        #expect(!viewModel.isGenerated(.model))
    }

    @Test("Without the model the review has the code's MAC and serial and no marks")
    func withoutModel() async throws {
        let viewModel = viewModel(model: nil)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.values == LabelValues(serial: "NW12K4471093", mac: "00:1E:42:7A:9C:31"))
        #expect(LabelReading.Field.allCases.allSatisfy { !viewModel.isGenerated($0) })
    }

    @Test("Save writes the reviewed values as user-confirmed; Retake drops them")
    func saveAndRetake() async throws {
        let viewModel = viewModel(model: LabelFields(status: .found, model: "NW-AC1200"))
        try await viewModel.read(#require(Self.image))
        let device = LocalDevice(ipAddress: "192.168.1.10", macAddress: "")
        #expect(device.modelName == nil, "Reading writes nothing")
        #expect(viewModel.save(to: device, among: [device]) == .written)
        #expect(device.identity.model == IdentityValue("NW-AC1200", source: .userConfirmed))
        #expect(device.macAddress == "00:1E:42:7A:9C:31")
        viewModel.retake()
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.values == LabelValues())
    }
}
