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
    /// Updates sent to a request that hasn't been made yet, delivered when it is (#606).
    private var early: [Int: [InsightUpdate]] = [:]
    private var evidence: [DeviceEvidence] = []
    private var scripted: DeviceSuggestion?

    init(isAvailable: Bool = true, suggestion: DeviceSuggestion? = nil) {
        available = isAvailable
        scripted = suggestion
    }

    var isAvailable: Bool {
        get { lock.withLock { available } }
        set { lock.withLock { available = newValue } }
    }

    var requests: [InsightRequest] { lock.withLock { received } }
    var suggestionRequests: [DeviceEvidence] { lock.withLock { evidence } }

    /// The answer to every later `suggestIdentity` call.
    var suggestion: DeviceSuggestion? {
        get { lock.withLock { scripted } }
        set { lock.withLock { scripted = newValue } }
    }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            let queued: [InsightUpdate] = lock.withLock {
                received.append(request)
                continuations.append(continuation)
                return early.removeValue(forKey: continuations.count - 1) ?? []
            }
            for update in queued {
                Self.deliver(update, on: continuation)
            }
        }
    }

    /// Sends `update` on the stream of the `index`th request. A state object starts its model call
    /// from a task, so under load a test can send before that call is made: the update is kept
    /// and delivered when the request arrives, instead of crashing on a missing stream (#606).
    func send(_ update: InsightUpdate, to index: Int = 0) {
        let continuation: AsyncStream<InsightUpdate>.Continuation? = lock.withLock {
            guard index < continuations.count else {
                early[index, default: []].append(update)
                return nil
            }
            return continuations[index]
        }
        if let continuation {
            Self.deliver(update, on: continuation)
        }
    }

    private static func deliver(_ update: InsightUpdate, on continuation: AsyncStream<InsightUpdate>.Continuation) {
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
