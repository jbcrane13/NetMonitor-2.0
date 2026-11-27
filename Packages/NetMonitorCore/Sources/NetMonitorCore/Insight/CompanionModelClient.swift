import Foundation
import Observation
import Synchronization

/// What a `modelRequest` came to.
public enum ModelClientResult: Sendable, Equatable {
    /// The Mac model's answer, still unchecked: the feature checks it against what the user typed.
    case output(ModelOutput)
    /// The Mac is scanning or already answering: try again in a moment.
    case busy
    /// Nothing usable: no capable Mac, a failed send, a drop, a timeout, a refusal or a reply
    /// that broke the rules. The feature falls back to its path without the model.
    case unavailable
}

/// The iPhone's side of `modelRequest` (#586): sends a typed rule or symptom to the connected
/// Mac, only for a schema the Mac's **latest** heartbeat lists, and waits for its one answer.
///
/// Every request is bound to the link it was sent on, a fresh ID and its exact schema: a reply on
/// another link, for another schema, with both or neither of output and failure, or with a field
/// over its limit is not used. Pending state is removed before the request completes, so a second
/// reply finds nothing. When the phone gives up (its timeout, or the caller's task is cancelled)
/// it sends `modelCancel`, after the request's own send has finished, so the Mac never sees the
/// cancel first.
///
/// The owning connection reports what arrives (`received(heartbeat:onLink:)`,
/// `received(_:onLink:)`) and when the link ends (`disconnected()`). Requests carry what the user
/// typed, so nothing is logged. `offers(_:)` is observable, so a field that reads it redraws when
/// a capable Mac connects or stops offering the schema.
public final class CompanionModelClient: Sendable, Observable {
    /// Sends one message on one link; false when that link is gone or the send failed.
    public typealias Send = @Sendable (CompanionMessage, _ link: UUID) async -> Bool

    /// Longer than the Mac's own limit, `CompanionModelResponder.defaultTimeout`, so the Mac's
    /// `timeout` reply normally arrives first.
    public static let defaultTimeout: Duration = .seconds(13)

    private struct Pending {
        let schema: ModelSchema
        let link: UUID
        let continuation: CheckedContinuation<ModelClientResult, Never>
        var sending: Task<Void, Never>?
        var timer: Task<Void, Never>?
    }

    private struct State {
        var offered: Set<ModelSchema> = []
        /// The link the latest heartbeat came on.
        var link: UUID?
        var pending: [UUID: Pending] = [:]
    }

    private let send: Send
    private let timeout: Duration
    private let state = Mutex(State())
    private let registrar = ObservationRegistrar()

    public init(send: @escaping Send, timeout: Duration = defaultTimeout) {
        self.send = send
        self.timeout = timeout
    }

    /// Whether the connected Mac's latest heartbeat lists `schema`.
    public func offers(_ schema: ModelSchema) -> Bool {
        registrar.access(self, keyPath: \.offeredSchemas)
        return state.withLock { $0.offered.contains(schema) }
    }

    /// The schemas the connected Mac offers now.
    public var offeredSchemas: Set<ModelSchema> {
        registrar.access(self, keyPath: \.offeredSchemas)
        return state.withLock { $0.offered }
    }

    /// Records the schemas a heartbeat from the Mac lists, on `link`.
    public func received(heartbeat: HeartbeatPayload, onLink link: UUID) {
        let offered = heartbeat.offeredSchemas
        let changed = state.withLock { state in
            state.link = link
            return state.offered != offered
        }
        guard changed else { return }
        registrar.withMutation(of: self, keyPath: \.offeredSchemas) {
            state.withLock { $0.offered = offered }
        }
    }

    /// Ends the request `response` answers, if it is pending on `link` for the response's
    /// schema. Anything else is ignored.
    public func received(_ response: ModelResponsePayload, onLink link: UUID) {
        let id = response.requestID
        let result: ModelClientResult? = state.withLock { state in
            guard let pending = state.pending[id], pending.link == link else { return nil }
            switch response.result(expecting: pending.schema) {
            case .output(let output)?: return .output(output)
            case .failure(.busy)?: return .busy
            case .failure?, nil: return .unavailable
            }
        }
        if let result {
            finish(id, with: result)
        }
    }

    /// The link ended: the Mac offers nothing, and every request in flight ends unavailable.
    public func disconnected() {
        // Nothing offered first, so no request can start between this and failing those in flight.
        let changed = state.withLock { state in
            state.link = nil
            return !state.offered.isEmpty
        }
        if changed {
            registrar.withMutation(of: self, keyPath: \.offeredSchemas) {
                state.withLock { $0.offered = [] }
            }
        }
        let ids = state.withLock { Array($0.pending.keys) }
        for id in ids {
            finish(id, with: .unavailable)
        }
    }

    /// Asks the Mac's model to read `input`. Returns at once with `.unavailable` when the Mac
    /// doesn't offer the schema or the input is over its limit.
    public func request(_ input: ModelInput) async -> ModelClientResult {
        guard input.isWithinLimits else { return .unavailable }
        let id = UUID()
        let message = CompanionMessage.modelRequest(ModelRequestPayload(requestID: id, input: input))
        guard let frame = try? message.encodeLengthPrefixed(), frame.count - 4 <= ModelSchema.maximumFrameSize else {
            return .unavailable
        }
        let schema = input.schema
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let link: UUID? = state.withLock { state in
                    guard state.offered.contains(schema), let link = state.link else { return nil }
                    state.pending[id] = Pending(schema: schema, link: link, continuation: continuation)
                    return link
                }
                guard let link else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                // Cancelled before the request was registered: send nothing.
                guard !Task.isCancelled else {
                    finish(id, with: .unavailable)
                    return
                }
                let send = send
                let timeout = timeout
                let sending = Task { [weak self] in
                    if await !send(message, link) {
                        self?.finish(id, with: .unavailable)
                    }
                }
                let timer = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.giveUp(id)
                }
                let stillPending = state.withLock { state in
                    guard state.pending[id] != nil else { return false }
                    state.pending[id]?.sending = sending
                    state.pending[id]?.timer = timer
                    return true
                }
                if !stillPending {
                    timer.cancel()
                }
            }
        } onCancel: {
            giveUp(id)
        }
    }

    /// The phone stops waiting for `id`: it ends unavailable, and the Mac is told to stop once
    /// the request itself has gone out.
    private func giveUp(_ id: UUID) {
        guard let pending = remove(id) else { return }
        pending.timer?.cancel()
        pending.continuation.resume(returning: .unavailable)
        let send = send
        let sending = pending.sending
        let link = pending.link
        Task {
            await sending?.value
            _ = await send(.modelCancel(ModelCancelPayload(requestID: id)), link)
        }
    }

    private func finish(_ id: UUID, with result: ModelClientResult) {
        guard let pending = remove(id) else { return }
        pending.timer?.cancel()
        pending.continuation.resume(returning: result)
    }

    private func remove(_ id: UUID) -> Pending? {
        state.withLock { $0.pending.removeValue(forKey: id) }
    }
}
