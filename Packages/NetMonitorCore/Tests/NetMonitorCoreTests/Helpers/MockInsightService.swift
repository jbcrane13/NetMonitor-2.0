import Foundation
import NetMonitorCore

/// An insight service the test drives by hand. Uses only NetMonitorCore's public API, so the
/// app test targets can compile this same file.
///
/// - Explanations: each `explain` call is recorded in ``requests``; finish it with ``send(_:to:)``.
/// - Suggestions: each `suggestIdentity` call is recorded in ``suggestionRequests`` and
///   answered with ``suggestion``.
final class MockInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var available: Bool
    private var continuations: [AsyncStream<InsightUpdate>.Continuation] = []
    private var received: [InsightRequest] = []
    private var evidence: [DeviceEvidence] = []
    private var scripted: DeviceSuggestion?

    init(isAvailable: Bool = true, suggestion: DeviceSuggestion? = nil) {
        available = isAvailable
        scripted = suggestion
    }

    var isAvailable: Bool { lock.withLock { available } }
    var requests: [InsightRequest] { lock.withLock { received } }
    var suggestionRequests: [DeviceEvidence] { lock.withLock { evidence } }

    /// The answer to every later `suggestIdentity` call.
    var suggestion: DeviceSuggestion? {
        get { lock.withLock { scripted } }
        set { lock.withLock { scripted = newValue } }
    }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            lock.withLock {
                received.append(request)
                continuations.append(continuation)
            }
        }
    }

    /// Sends `update` on the stream of the `index`th request.
    func send(_ update: InsightUpdate, to index: Int = 0) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(update)
        if case .partial = update {
            return
        }
        continuation.finish()
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        lock.withLock {
            self.evidence.append(evidence)
            return scripted
        }
    }
}
