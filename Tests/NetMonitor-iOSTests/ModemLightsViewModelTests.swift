import CoreGraphics
import Foundation
import NetMonitorCore
import Testing
import UIKit
@testable import NetMonitor_iOS

/// #558: reading a modem's lights from a photo. The model is a scripted stand-in; the real
/// model is never called.
@Suite("Modem lights view model")
@MainActor
struct ModemLightsViewModelTests {
    /// Answers with a fixed reading and counts the photos it was asked about.
    private final class ScriptedExtractor: ModemLightExtractorProtocol, @unchecked Sendable {
        let answer: ModemPanelAnswer?
        let delay: Duration?
        private(set) var calls = 0
        init(_ answer: ModemPanelAnswer?, delay: Duration? = nil) {
            self.answer = answer
            self.delay = delay
        }

        var isAvailable: Bool { true }
        func readLights(in image: CGImage) async -> ModemPanelAnswer? {
            calls += 1
            if let delay {
                try? await Task.sleep(for: delay)
            }
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

    private func viewModel(_ extractor: ScriptedExtractor, scanning: Bool = false) -> ModemLightsViewModel {
        ModemLightsViewModel(extractor: extractor, isScanning: { scanning }, testImage: { nil })
    }

    @Test("A reading is handed to the troubleshooter; a photo that isn't a panel is not (#625)")
    func readingGoesToTheTroubleshooter() async throws {
        var handed: [ModemPanelReport] = []
        let viewModel = ModemLightsViewModel(
            extractor: ScriptedExtractor(Self.redInternet), isScanning: { false }, testImage: { nil }, onReading: { handed.append($0) }
        )
        try await viewModel.read(Self.image)
        #expect(handed == [ModemPanelReport(answer: Self.redInternet)])

        let notAPanel = ModemLightsViewModel(
            extractor: ScriptedExtractor(ModemPanelAnswer(status: .unsupported, lights: [])), isScanning: { false }, testImage: { nil },
            onReading: { handed.append($0) }
        )
        try await notAPanel.read(Self.image)
        #expect(handed.count == 1)
    }

    @Test("A reading the user closed the sheet on is not handed over (#625)")
    func cancelledReadingIsNotHandedOver() async throws {
        var handed = 0
        let extractor = ScriptedExtractor(Self.redInternet, delay: .seconds(1))
        let viewModel = ModemLightsViewModel(extractor: extractor, isScanning: { false }, testImage: { nil }, onReading: { _ in handed += 1 })
        let image = try Self.image
        let task = Task { await viewModel.read(image) }
        // Cancel while the model is reading, not before it starts.
        await waitUntil { extractor.calls == 1 }
        #expect(extractor.calls == 1)
        task.cancel()
        await task.value
        #expect(handed == 0)
    }

    @Test("A red Internet light is shown with the app's own lines; nothing is model-written")
    func redInternetReading() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet))
        try await viewModel.read(Self.image)
        guard case let .result(report) = viewModel.phase else {
            Issue.record("Expected a result, got \(viewModel.phase)")
            return
        }
        #expect(report.headline == "1 light shows a problem. 1 light reads as off: check it.")
        #expect(report.keyPoints.first == "Internet light reads as red: this normally means the modem has no internet connection.")
    }

    @Test("An Internet light read as off is a light to check, not a problem")
    func offInternetIsACheck() async throws {
        let answer = ModemPanelAnswer(status: .panel, lights: [.init(label: "POWER", color: .green), .init(label: "INTERNET", color: .off)])
        let viewModel = viewModel(ScriptedExtractor(answer))
        try await viewModel.read(Self.image)
        guard case let .result(report) = viewModel.phase else {
            Issue.record("Expected a result, got \(viewModel.phase)")
            return
        }
        #expect(report.headline == "1 light reads as off: check it.")
        #expect(report.keyPoints.first == "Internet reads as off. If it is dark, the modem isn't online.")
    }

    @Test("A photo that can't be opened leaves the user choosing another, with the shared message")
    func unreadablePhoto() async {
        let extractor = ScriptedExtractor(Self.redInternet)
        let viewModel = viewModel(extractor)
        await viewModel.readPhoto { Data("not an image".utf8) }
        #expect(extractor.calls == 0)
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.errorMessage == "That photo couldn't be opened. Try another one.")
    }

    @Test("During a network scan the model isn't asked, and the user is told to wait")
    func scanning() async throws {
        let extractor = ScriptedExtractor(Self.redInternet)
        let viewModel = viewModel(extractor, scanning: true)
        try await viewModel.read(Self.image)
        #expect(extractor.calls == 0)
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.errorMessage == "A network scan is running. Try again when it finishes.")
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
        #expect(viewModel.errorMessage == "The lights couldn't be read. Try another photo.")
    }

    @Test("Closing the sheet mid-read stops the reading: no result")
    func cancelledRead() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet, delay: .seconds(5)))
        let task = try viewModel.takePhoto(UIImage(cgImage: Self.image))
        viewModel.cancel()
        await task.value
        #expect(viewModel.phase != .result(ModemPanelReport(answer: Self.redInternet)))
    }

    @Test("Retake drops the reading")
    func retake() async throws {
        let viewModel = viewModel(ScriptedExtractor(Self.redInternet))
        try await viewModel.read(Self.image)
        viewModel.retake()
        #expect(viewModel.phase == .choosing)
        #expect(viewModel.errorMessage == nil)
    }
}
