import Foundation
import Observation
import Synchronization

/// The iPhone's side of insight over the companion link (#457): sends an `InsightRequest` to a
/// connected Mac that advertised `CompanionCapability.insight`, and streams its one answer.
///
/// The owning connection reports what arrives (`received(heartbeat:)`, `received(_:)`) and
/// when the link ends (`disconnected()`). A request ends `.failed` when it is too large or the
/// Mac refuses it, and `.unreachable` when no capable Mac is connected, the send fails, the link
/// drops, the Mac is busy or times out, or no answer comes within `timeout`: callers fall back
/// to their path without the model, and ask again later only after `.unreachable`. Requests carry addresses and hostnames, so nothing is logged.
///
/// `isAvailable` is observable, so a view that reads it, directly or through
/// `RoutedInsightService`, redraws when a capable Mac connects or goes away.
public final class CompanionInsightClient: Sendable, Observable {
    /// Sends one message to the Mac; false when it couldn't be sent.
    public typealias Send = @Sendable (CompanionMessage) async -> Bool
    /// Sends one message to the Mac only if `isWanted` (the user's consent) still holds where the
    /// send itself runs (#635); false when it doesn't or the send failed.
    public typealias SendIf = @Sendable (CompanionMessage, _ isWanted: @escaping @Sendable () -> Bool) async -> Bool

    /// Longer than the Mac's own limit, `CompanionInsightResponder.defaultTimeout`, so the
    /// Mac's timeout reply normally arrives first. An older Mac's error reply carries no
    /// request id, so this is also what ends a request one never answers.
    public static let defaultTimeout: Duration = .seconds(25)

    private struct Pending {
        let continuation: AsyncStream<InsightUpdate>.Continuation
        /// Whether the request may still go out and its answer be used (#635).
        let isWanted: @Sendable () -> Bool
    }

    private struct State {
        var macOffersInsight = false
        var pending: [UUID: Pending] = [:]
    }

    private let send: SendIf
    private let timeout: Duration
    private let state = Mutex(State())
    private let registrar = ObservationRegistrar()

    public convenience init(send: @escaping Send, timeout: Duration = defaultTimeout) {
        self.init(sendIf: { message, isWanted in isWanted() ? await send(message) : false }, timeout: timeout)
    }

    /// With a send that checks the request's condition itself, in the same step as the send (#635).
    public init(sendIf: @escaping SendIf, timeout: Duration = defaultTimeout) {
        send = sendIf
        self.timeout = timeout
    }

    /// Whether the connected Mac answers insight requests now.
    public var isAvailable: Bool {
        registrar.access(self, keyPath: \.isAvailable)
        return state.withLock { $0.macOffersInsight }
    }

    /// Records the capabilities in a heartbeat from the Mac.
    public func received(heartbeat: HeartbeatPayload) {
        setAvailable(heartbeat.offersInsight)
    }

    /// Observers hear only of a change: heartbeats repeat the same capabilities.
    private func setAvailable(_ offersInsight: Bool) {
        guard state.withLock({ $0.macOffersInsight != offersInsight }) else { return }
        registrar.withMutation(of: self, keyPath: \.isAvailable) {
            state.withLock { $0.macOffersInsight = offersInsight }
        }
    }

    /// Ends the request `response` answers. A response to no pending request is ignored.
    public func received(_ response: InsightResponsePayload) {
        let wanted = state.withLock { $0.pending[response.requestID]?.isWanted() }
        // An answer the user no longer wants (consent withdrawn meanwhile) is dropped (#635).
        finish(response.requestID, with: wanted == false ? .unreachable : Self.update(for: response))
    }

    /// The link ended: the Mac no longer counts as available and every request in flight fails.
    public func disconnected() {
        // Unavailable first, so no request can start between this and failing those in flight.
        setAvailable(false)
        // A named parameter, not `$0` inside `defer`: Xcode 16.4's compiler rejects that.
        let pending = state.withLock { state in
            let values = Array(state.pending.values)
            state.pending.removeAll()
            return values
        }
        for pending in pending {
            pending.continuation.yield(.unreachable)
            pending.continuation.finish()
        }
    }

    /// Asks the Mac to word `request`, ending with `.finished`, `.failed` (refused, or too
    /// large to send) or `.unreachable` (no capable Mac, a failed send, a drop, a busy or
    /// timed-out Mac, or no answer within `timeout`). No partial text: the Mac sends its whole,
    /// checked answer at once.
    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        explain(request, while: { true })
    }

    /// As `explain(_:)`, while `isWanted` holds (#635): it is checked right before the request goes
    /// out (and by the send itself) and before an answer is used.
    public func explain(_ request: InsightRequest, while isWanted: @escaping @Sendable () -> Bool) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            let payload = InsightRequestPayload(requestID: UUID(), request: request)
            let id = payload.requestID
            guard let encoded = try? JSONEncoder().encode(payload),
                  encoded.count <= InsightRequestPayload.maximumEncodedSize
            else {
                continuation.yield(.failed)
                continuation.finish()
                return
            }
            guard state.withLock({ state in
                guard state.macOffersInsight else { return false }
                state.pending[id] = Pending(continuation: continuation, isWanted: isWanted)
                return true
            })
            else {
                continuation.yield(.unreachable)
                continuation.finish()
                return
            }
            // Set before the tasks start, so a consumer that stops at once still cancels them.
            let tasks = Mutex<[Task<Void, Never>]>([])
            continuation.onTermination = { [weak self] _ in
                tasks.withLock { $0.forEach { $0.cancel() } }
                self?.state.withLock { _ = $0.pending.removeValue(forKey: id) }
            }
            let send = send
            let timeout = timeout
            // The deadline runs from now, not from the end of the send: a send that stalls on
            // the link must not hold the request open.
            let deadline = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(id, with: .unreachable)
            }
            let sending = Task { [weak self] in
                guard isWanted(), await send(.insightRequest(payload), isWanted) else {
                    self?.finish(id, with: .unreachable)
                    return
                }
            }
            tasks.withLock { $0 = [deadline, sending] }
            // The consumer may have stopped before the tasks were recorded.
            if state.withLock({ $0.pending[id] == nil }) {
                deadline.cancel()
                sending.cancel()
            }
        }
    }

    /// The answer, or the failure as lasting (`.failed`) or for now (`.unreachable`).
    static func update(for response: InsightResponsePayload) -> InsightUpdate {
        if let answer = response.answer {
            return .finished(answer)
        }
        switch response.failureReason {
        case .refused, .tooLarge: return .failed
        case .unavailable, .timeout, .busy, nil: return .unreachable
        }
    }

    private func finish(_ id: UUID, with update: InsightUpdate) {
        guard let pending = state.withLock({ $0.pending.removeValue(forKey: id) }) else { return }
        pending.continuation.yield(update)
        pending.continuation.finish()
    }
}

/// Whether a routed request could be answered now (#457).
public enum InsightAvailability: Sendable, Equatable {
    /// This device's model, or a Mac the user agreed to use.
    case available
    /// A connected Mac could answer what this device's model can't, but the user hasn't been
    /// asked. Not available: nothing is sent until the user agrees. A card offers the prompt.
    case needsConsent
    /// Nothing can answer.
    case unavailable
}

/// Where an insight answer was written.
public enum InsightSource: String, Sendable, Equatable, Codable {
    /// By the model on this device.
    case device
    /// By the model on the connected Mac, over the companion link (#457).
    case mac

    /// The writer, as the generated-text markers name it: "Written by \(modelName) …".
    public var modelName: String {
        switch self {
        case .device: "the on-device model"
        case .mac: "the on-device model on your Mac"
        }
    }
}

/// The iPhone's insight service (#457): the local model when it's available, else a connected
/// Mac that offers insight, else none. `isAvailable` follows that order, so features built on
/// `InsightServiceProtocol` light up on an ineligible phone without changes of their own.
/// Identity suggestions use the local model only.
public struct RoutedInsightService: InsightServiceProtocol {
    public let local: any InsightServiceProtocol
    public let mac: CompanionInsightClient
    /// The user's answer to "Use your Mac for on-device AI?": the Mac is used only once they agree.
    public let consent: MacInsightConsent

    public init(local: any InsightServiceProtocol, mac: CompanionInsightClient, consent: MacInsightConsent) {
        self.local = local
        self.mac = mac
        self.consent = consent
    }

    /// Whether a request may go to the Mac now: it offers insight and the user agreed.
    private var macRoute: Bool { mac.isAvailable && consent.isAllowed }

    public var isAvailable: Bool { local.isAvailable || macRoute }

    /// Whether a request could be answered now, and by whom.
    public var availability: InsightAvailability {
        if local.isAvailable {
            return .available
        }
        guard mac.isAvailable else { return .unavailable }
        switch consent.decision {
        case true?: return .available
        case nil: return .needsConsent
        case false?: return .unavailable
        }
    }

    /// Whether to ask the user about the Mac now: it could answer what the local model can't,
    /// and the user hasn't been asked.
    public var shouldAskForMac: Bool { availability == .needsConsent }

    /// Who would write an answer asked for now; nil when neither can.
    public var answerSource: InsightSource? {
        local.isAvailable ? .device : macRoute ? .mac : nil
    }

    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        if local.isAvailable {
            return local.explain(request)
        }
        // Under the consent generation it began with (#635): nothing is sent, and no answer used,
        // once the user withdrew it, even if they agreed again; withdrawing ends it at once.
        guard let generation = consent.allowedGeneration else {
            return AsyncStream { continuation in
                continuation.yield(.unreachable)
                continuation.finish()
            }
        }
        let consent = consent
        let isCurrent: @Sendable () -> Bool = { consent.allowedGeneration == generation }
        let answers = mac.explain(request, while: isCurrent)
        return AsyncStream { continuation in
            let relay = Task {
                for await update in answers {
                    continuation.yield(update)
                }
                continuation.finish()
            }
            // The final update goes out before the relay is cancelled, so its own finish can't
            // overtake it.
            let handler = consent.addWithdrawalHandler {
                continuation.yield(.unreachable)
                continuation.finish()
                relay.cancel()
            }
            continuation.onTermination = { _ in
                relay.cancel()
                consent.removeWithdrawalHandler(handler)
            }
            // Withdrawn between the check and registering the handler.
            if !isCurrent() {
                continuation.yield(.unreachable)
                continuation.finish()
                relay.cancel()
            }
        }
    }

    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        local.isAvailable ? await local.suggestIdentity(evidence) : nil
    }
}

extension InsightService {
    /// Who writes `service`'s answers when asked now: the Mac for a routed service relying on
    /// it, this device otherwise.
    public static func source(of service: any InsightServiceProtocol) -> InsightSource {
        (service as? RoutedInsightService)?.answerSource ?? .device
    }
}
