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
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
