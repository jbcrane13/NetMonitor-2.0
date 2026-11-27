import Foundation
import NetMonitorCore

/// One link's `modelRequest`s (#586): which task runs each request ID, and the last spent IDs.
/// A request whose ID is running or spent is dropped, so a duplicate ID, or a request whose
/// `modelCancel` arrived first, never runs.
struct CompanionModelRequestLedger {
    /// How many spent IDs a link remembers.
    static let spentLimit = 32

    /// Request ID → the deferred task running it.
    private var running: [UUID: UUID] = [:]
    private var spent: [UUID] = []

    /// Whether a request with `id` may start; nil, for a message that isn't a model request, may.
    func admits(_ id: UUID?) -> Bool {
        guard let id else { return true }
        return running[id] == nil && !spent.contains(id)
    }

    /// Records the task running model request `id`; nothing for nil.
    mutating func start(_ id: UUID?, task: UUID) {
        if let id {
            running[id] = task
        }
    }

    /// The task ended: its request ID is spent. Nothing for a task that ran no model request.
    mutating func finish(task: UUID) {
        guard let id = running.first(where: { $0.value == task })?.key else { return }
        running[id] = nil
        spend(id)
    }

    /// The phone cancelled `id`: the task to cancel, if it is running. The ID is spent either way.
    mutating func cancel(_ id: UUID) -> UUID? {
        let task = running.removeValue(forKey: id)
        spend(id)
        return task
    }

    private mutating func spend(_ id: UUID) {
        guard !spent.contains(id) else { return }
        spent.append(id)
        if spent.count > Self.spentLimit {
            spent.removeFirst(spent.count - Self.spentLimit)
        }
    }
}

// MARK: - Model requests on a link

extension CompanionService {
    /// Whether `message` is handled on its own instead of in its batch's order: a model request
    /// can take seconds, and the frames behind it, such as heartbeats, must not wait (#457, #586).
    static func answersOffBatch(_ message: CompanionMessage) -> Bool {
        switch message {
        case .insightRequest, .modelRequest: true
        default: false
        }
    }

    /// The `busy` reply to a model request over the link's cap.
    static func busyReply(to message: CompanionMessage) -> CompanionMessage? {
        switch message {
        case .insightRequest(let request):
            .insightResponse(InsightResponsePayload(requestID: request.requestID, failure: .busy))
        case .modelRequest(let request):
            .modelResponse(ModelResponsePayload(requestID: request.requestID, schema: request.schema, failure: .busy))
        default:
            nil
        }
    }

    /// The request ID of a `modelRequest`, which the link's ledger tracks.
    static func modelRequestID(of message: CompanionMessage) -> UUID? {
        if case .modelRequest(let request) = message {
            return request.requestID
        }
        return nil
    }
}
