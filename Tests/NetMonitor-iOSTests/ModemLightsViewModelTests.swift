import CoreGraphics
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// #558: reading a modem's lights from a photo. The model is a scripted stand-in; the real
/// model is never called.
@Suite("Modem lights view model")
@MainActor
struct ModemLightsViewModelTests {
    /// Answers with a fixed reading and counts the photos it was asked about.
    private final class ScriptedExtractor: ModemLightExtractorProtocol, @unchecked Sendable {
        let answer: ModemPanelAnswer?
        private(set) var calls = 0
        init(_ answer: ModemPanelAnswer?) {
            self.answer = answer
        }

        var isAvailable: Bool { true }
        func readLights(in image: CGImage) async -> ModemPanelAnswer? {
            calls += 1
            return answer
        }
    }

    private static let redInternet = ModemPanelAnswer(status: .panel, lights: [
        .init(label: "POWER", color: .green), .init(label: "INTERNET", color: .red), .init(label: "LAN 2", color: .off)
    ])

    private static var image: CGImage {
        get throws {
            let context = try #require(CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(context.makeImage())
        }
    }

    private func viewModel(
        _ extractor: ScriptedExtractor,
        wording: (any InsightServiceProtocol)? = nil,
        scanning: Bool = false
    ) -> ModemLightsViewModel {
        ModemLightsViewModel(
            extractor: extractor,
            insight: wording ?? UnavailableInsightService(),
            isScanning: { scanning },
            testImage: { nil }
        )
    }

    @Test("A red Internet light is shown with the app's meaning first, and the model's wording under it")
    func redInternetReading() async throws {
        let wording = "The Internet light is red, so the modem has no internet connection."
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet), wording: FixedAnswerInsightService(answer: wording))
        try await viewModel.read(Self.image)
        guard case let .result(report) = viewModel.phase else {
            Issue.record("Expected a result, got \(viewModel.phase)")
            return
        }
        #expect(report.headline == "1 light shows a problem.")
        #expect(report.keyPoints.first == "Internet light is red: the modem has no internet connection.")
        #expect(viewModel.wording == .written(wording))
    }

    @Test("Wording that states a number the app didn't is dropped; the app's lines stay")
    func ungroundedWording() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet), wording: FixedAnswerInsightService(answer: "4 of your lights are fine."))
        try await viewModel.read(Self.image)
        #expect(viewModel.wording == .none)
        #expect(viewModel.phase == .result(ModemPanelReport(answer: Self.redInternet)))
    }

    @Test("Without the text model the reading still shows, unworded")
    func unavailableWording() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet))
        try await viewModel.read(Self.image)
        #expect(viewModel.phase == .result(ModemPanelReport(answer: Self.redInternet)))
        #expect(viewModel.wording == .none)
    }

    @Test("During a network scan the model isn't asked, and the user is told to wait")
    func scanning() async throws {
        let extractor = ScriptedExtractor(Self.redInternet)
        let viewModel = viewModel(extractor, scanning: true)
        try await viewModel.read(Self.image)
        #expect(extractor.calls == 0)
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.photoError == "A network scan is running. Try again when it finishes.")
    }

    @Test("A photo that isn't a panel says so")
    func notAPanel() async throws {
        let viewModel = viewModel(ScriptedExtractor(ModemPanelAnswer(status: .unsupported, lights: [.init(label: "POWER", color: .green)])))
        try await viewModel.read(Self.image)
        #expect(viewModel.phase == .notAPanel)
    }

    @Test("A model that can't answer leaves the user choosing another photo")
    func noAnswer() async throws {
        let viewModel = viewModel(ScriptedExtractor(nil))
        try await viewModel.read(Self.image)
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.photoError == "The lights couldn't be read. Try another photo.")
    }

    @Test("Retake drops the reading and its wording")
    func retake() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet), wording: FixedAnswerInsightService(answer: "The Internet light is red."))
        try await viewModel.read(Self.image)
        viewModel.retake()
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.wording == .none)
        #expect(viewModel.photoError == nil)
    }
}
