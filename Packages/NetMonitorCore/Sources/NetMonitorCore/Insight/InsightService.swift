import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The insight service the apps use: the on-device model on iOS 27 / macOS 27 and later,
/// and a service that is never available everywhere else (#448).
public enum InsightService {
    public static let shared: any InsightServiceProtocol = make()

    static func make() -> any InsightServiceProtocol {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemInsightService()
        }
        #endif
        return UnavailableInsightService()
    }
}

/// Used where the on-device model does not exist. Callers hide their affordance.
public struct UnavailableInsightService: InsightServiceProtocol {
    public init() {}
    public var isAvailable: Bool { false }
    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.failed)
            continuation.finish()
        }
    }

    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        nil
    }
}

/// Suggests the same identity for every device, for UI tests that need a suggestion on
/// screen without the on-device model (#449). Explanations always fail.
public struct FixedSuggestionInsightService: InsightServiceProtocol {
    /// The suggestion the apps' UI tests expect: a printer from a maker no fixture uses.
    public static let uiTestSuggestion = DeviceSuggestion(
        deviceType: .printer, maker: "Brother", model: "HL-L2350DW", confidence: .high
    )

    private let suggestion: DeviceSuggestion

    public init(suggestion: DeviceSuggestion = Self.uiTestSuggestion) {
        self.suggestion = suggestion
    }

    public var isAvailable: Bool { true }

    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.failed)
            continuation.finish()
        }
    }

    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        suggestion
    }
}

/// Answers every request at once with a fixed text, for UI tests that need a model-written
/// summary on screen without the on-device model (#491 S6). The answer still goes through
/// `InsightSummarizer`'s checks, so it must state nothing the request doesn't.
public struct FixedAnswerInsightService: InsightServiceProtocol {
    private let answer: String

    public init(answer: String) {
        self.answer = answer
    }

    public var isAvailable: Bool { true }

    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }

    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        nil
    }
}

#if canImport(FoundationModels)
/// Explains requests with the system language model. Everything stays on the device.
/// Prompts carry addresses and hostnames, so nothing here is logged.
@available(iOS 27.0, macOS 27.0, *)
struct SystemInsightService: InsightServiceProtocol {
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            let task = Task {
                // Interactive: while it runs, companion requests are answered busy (#586).
                await ModelAdmission.shared.runLocal(.interactive) {
                    await Self.stream(request, into: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func stream(_ request: InsightRequest, into continuation: AsyncStream<InsightUpdate>.Continuation) async {
                do {
                    let session = LanguageModelSession(instructions: request.kind.instructions)
                    var text = ""
                    // Greedy sampling: the same result gets the same explanation, and the model
                    // stays closest to the facts it was given.
                    let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: request.kind.responseTokenLimit)
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        text = snapshot.content
                        continuation.yield(.partial(text))
                    }
                    continuation.yield(text.isEmpty ? .failed : .finished(text))
                } catch {
                    continuation.yield(.failed)
                }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        do {
            let session = LanguageModelSession(instructions: DeviceEvidence.instructions)
            // Guided generation into a typed answer; greedy so the same evidence gets the same answer.
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
            let response = try await session.respond(to: evidence.prompt, generating: GeneratedIdentity.self, options: options)
            return response.content.suggestion
        } catch {
            return nil
        }
    }
}

/// The typed answer the model fills in for ``SystemInsightService/suggestIdentity(_:)``.
@available(iOS 27.0, macOS 27.0, *)
@Generable
private struct GeneratedIdentity {
    @Guide(description: "The kind of device; unknown when the evidence does not show it", .anyOf(DeviceType.allCases.map(\.rawValue)))
    var deviceType: String
    @Guide(description: "The company whose brand is on the device, or empty when the evidence does not name it")
    var maker: String
    @Guide(description: "The device's product model, or empty when the evidence does not name it")
    var model: String
    @Guide(description: "How well the evidence supports the answer", .anyOf(["low", "medium", "high"]))
    var confidence: String

    var suggestion: DeviceSuggestion {
        func present(_ text: String) -> String? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let type = DeviceType(rawValue: deviceType)
        return DeviceSuggestion(
            deviceType: type == .unknown ? nil : type,
            maker: present(maker),
            model: present(model),
            confidence: DeviceSuggestion.Confidence(rawValue: confidence) ?? .low
        )
    }
}
#endif
