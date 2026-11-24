import CoreGraphics
import Foundation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The label services the apps use (#456): Vision OCR, and the on-device model on iOS 27 /
/// macOS 27 and later.
public enum LabelServices {
    public static let extractor: any LabelFieldExtractorProtocol = makeExtractor()
    public static let recognizer: any LabelTextRecognizerProtocol = VisionLabelTextRecognizer()

    static func makeExtractor() -> any LabelFieldExtractorProtocol {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemLabelFieldExtractor()
        }
        #endif
        return FixedLabelFieldExtractor(answer: nil)
    }
}

/// Answers every label with the same fields, for UI tests that need model-filled fields without
/// the on-device model (#456). The answer still goes through ``LabelReader``'s checks.
public struct FixedLabelFieldExtractor: LabelFieldExtractorProtocol {
    private let answer: LabelFields?

    public init(answer: LabelFields?) {
        self.answer = answer
    }

    public func extractFields(from lines: [String]) async -> LabelFields? {
        answer
    }
}

// MARK: - OCR

/// Reads text with Vision's accurate recognizer, without language correction so serials keep
/// their characters. Everything stays on the device; the text is never logged.
public struct VisionLabelTextRecognizer: LabelTextRecognizerProtocol {
    public init() {}

    public func prewarm() async {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let image = context?.makeImage() else { return }
        _ = await recognizeText(in: image)
    }

    public func recognizeText(in image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

// MARK: - On-device model

#if canImport(FoundationModels)
/// Fills label fields with the system language model through guided generation (#456).
@available(iOS 27.0, macOS 27.0, *)
struct SystemLabelFieldExtractor: LabelFieldExtractorProtocol {
    func extractFields(from lines: [String]) async -> LabelFields? {
        do {
            let session = LanguageModelSession(instructions: LabelFields.instructions)
            // Greedy: the same label gets the same fields.
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 160)
            let response = try await session.respond(to: LabelFields.prompt(for: lines), generating: GeneratedLabelFields.self, options: options)
            return response.content.fields
        } catch {
            return nil
        }
    }
}

/// The typed answer the model fills in. `status` comes first, so the model decides whether the
/// text is a label before it fills anything (the #447 spike: without an escape every input
/// became fields).
@available(iOS 27.0, macOS 27.0, *)
@Generable
private struct GeneratedLabelFields {
    @Guide(description: "found when the text is from a device label, otherwise notALabel", .anyOf(LabelFields.Status.allCases.map(\.rawValue)))
    var status: String
    @Guide(description: "The brand printed on the label, or empty")
    var maker: String
    @Guide(description: "The model number exactly as printed, or empty")
    var model: String
    @Guide(description: "The serial number exactly as printed after S/N or Serial, or empty")
    var serial: String
    @Guide(description: "The MAC address exactly as printed, or empty")
    var mac: String

    var fields: LabelFields {
        func present(_ text: String) -> String? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return LabelFields(
            status: LabelFields.Status(rawValue: status) ?? .notALabel,
            maker: present(maker),
            model: present(model),
            serial: present(serial),
            mac: present(mac)
        )
    }
}
#endif
