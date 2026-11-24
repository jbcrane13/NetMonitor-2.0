import Foundation
import Observation
import Synchronization

/// The iPhone's side of insight over the companion link (#457): sends an `InsightRequest` to a
/// connected Mac that advertised `CompanionCapability.insight`, and streams its one answer.
///
/// The owning connection reports what arrives (`received(heartbeat:)`, `received(_:)`) and
/// when the link ends (`disconnected()`). A request ends `.failed` when the Mac never
/// advertised the capability, the request is too large, the send fails, the Mac replies with a
/// failure, the link drops, or no answer comes within `timeout`: callers fall back to their
/// path without the model. Requests carry addresses and hostnames, so nothing is logged.
///
/// `isAvailable` is observable, so a view that reads it, directly or through
/// `RoutedInsightService`, redraws when a capable Mac connects or goes away.
public final class CompanionInsightClient: Sendable, Observable {
    /// Sends one message to the Mac; false when it couldn't be sent.
    public typealias Send = @Sendable (CompanionMessage) async -> Bool

    /// Longer than the Mac's own limit, `CompanionInsightResponder.defaultTimeout`, so the
    /// Mac's timeout reply normally arrives first. An older Mac's error reply carries no
    /// request id, so this is also what ends a request one never answers.
    public static let defaultTimeout: Duration = .seconds(25)

    private struct State {
        var macOffersInsight = false
        var pending: [UUID: AsyncStream<InsightUpdate>.Continuation] = [:]
    }

    private let send: Send
    private let timeout: Duration
    private let state = Mutex(State())
    private let registrar = ObservationRegistrar()

    public init(send: @escaping Send, timeout: Duration = defaultTimeout) {
        self.send = send
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
        finish(response.requestID, with: response.answer.map(InsightUpdate.finished) ?? .failed)
    }

    /// The link ended: the Mac no longer counts as available and every request in flight fails.
    public func disconnected() {
        // Unavailable first, so no request can start between this and failing those in flight.
        setAvailable(false)
        let pending = state.withLock {
            defer { $0.pending.removeAll() }
            return Array($0.pending.values)
        }
        for continuation in pending {
            continuation.yield(.failed)
            continuation.finish()
        }
    }

    /// Asks the Mac to word `request`, ending with `.finished` or `.failed`. No partial text:
    /// the Mac sends its whole, checked answer at once.
    public func explain(_ request: InsightRequest, devices: [InsightDeviceReference]? = nil) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            let payload = InsightRequestPayload(requestID: UUID(), request: request, devices: devices)
            let id = payload.requestID
            guard let encoded = try? JSONEncoder().encode(payload),
                  encoded.count <= InsightRequestPayload.maximumEncodedSize,
                  state.withLock({ state in
                      guard state.macOffersInsight else { return false }
                      state.pending[id] = continuation
                      return true
                  })
            else {
                continuation.yield(.failed)
                continuation.finish()
                return
            }
            let send = send
            let timeout = timeout
            // The deadline runs from now, not from the end of the send: a send that stalls on
            // the link must not hold the request open.
            let deadline = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(id, with: .failed)
            }
            let sending = Task { [weak self] in
                if await !send(.insightRequest(payload)) {
                    self?.finish(id, with: .failed)
                }
            }
            continuation.onTermination = { [weak self] _ in
                deadline.cancel()
                sending.cancel()
                self?.state.withLock { _ = $0.pending.removeValue(forKey: id) }
            }
        }
    }

    private func finish(_ id: UUID, with update: InsightUpdate) {
        guard let continuation = state.withLock({ $0.pending.removeValue(forKey: id) }) else { return }
        continuation.yield(update)
        continuation.finish()
    }
}

/// Where an insight answer was written.
public enum InsightSource: Sendable, Equatable {
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

    public init(local: any InsightServiceProtocol, mac: CompanionInsightClient) {
        self.local = local
        self.mac = mac
    }

    public var isAvailable: Bool { local.isAvailable || mac.isAvailable }

    /// Who would write an answer asked for now; nil when neither can.
    public var answerSource: InsightSource? {
        local.isAvailable ? .device : mac.isAvailable ? .mac : nil
    }

    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        local.isAvailable ? local.explain(request) : mac.explain(request)
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
