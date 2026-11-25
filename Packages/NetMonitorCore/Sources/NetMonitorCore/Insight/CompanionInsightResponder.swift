import Foundation

/// The Mac's side of insight over the companion link (#457): answers an iPhone's
/// `insightRequest` with the Mac's model, through the same `InsightSummarizer` checks the
/// apps use, so the phone only ever receives a grounded, filtered answer.
///
/// One request at a time: another arriving meanwhile is answered `busy`, as is any request
/// during a Mac scan. Prompts carry addresses and hostnames, so nothing here is logged.
public actor CompanionInsightResponder {
    /// How long the Mac's model may take to answer.
    public static let defaultTimeout: Duration = .seconds(20)

    private let service: any InsightServiceProtocol
    private let timeout: Duration
    private let isAllowed: @Sendable () async -> Bool
    private let isScanning: @Sendable () async -> Bool
    private var isAnswering = false

    public init(
        service: any InsightServiceProtocol,
        timeout: Duration = defaultTimeout,
        isAllowed: @escaping @Sendable () async -> Bool = { true },
        isScanning: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.service = service
        self.timeout = timeout
        self.isAllowed = isAllowed
        self.isScanning = isScanning
    }

    /// The capabilities a Mac heartbeat advertises: insight only while the model can be used,
    /// the user lets the Mac answer and the Mac isn't scanning. Nil keeps the field out of the
    /// heartbeat.
    nonisolated public func capabilities(allowed: Bool, isScanning: Bool = false) -> [String]? {
        allowed && !isScanning && service.isAvailable ? [CompanionCapability.insight] : nil
    }

    /// The reply to `payload`: the checked answer, or why there is none. `authorization` is the
    /// link's; it is checked at entry, after each suspension, and right before the model is
    /// asked, so a phone revoked meanwhile never reaches the model.
    public func respond(to payload: InsightRequestPayload, authorization: CompanionAuthorization) async -> InsightResponsePayload {
        let id = payload.requestID
        guard await authorization.isCurrent() else {
            return InsightResponsePayload(requestID: id, failure: .unavailable)
        }
        guard let encoded = try? JSONEncoder().encode(payload),
              encoded.count <= InsightRequestPayload.maximumEncodedSize else {
            return InsightResponsePayload(requestID: id, failure: .tooLarge)
        }
        guard let request = payload.request else {
            return InsightResponsePayload(requestID: id, failure: .refused)
        }
        guard await isAllowed(), service.isAvailable, await authorization.isCurrent() else {
            return InsightResponsePayload(requestID: id, failure: .unavailable)
        }
        // The scan check suspends, so `isAnswering` is checked and set after it, with no
        // suspension between: a request arriving meanwhile is busy.
        let scanning = await isScanning()
        guard await authorization.isCurrent() else {
            return InsightResponsePayload(requestID: id, failure: .unavailable)
        }
        guard !scanning, !isAnswering else {
            return InsightResponsePayload(requestID: id, failure: .busy)
        }
        isAnswering = true
        defer { isAnswering = false }

        // The last suspension was the authorisation check itself: submit only if it still holds.
        guard await authorization.isCurrent() else {
            return InsightResponsePayload(requestID: id, failure: .unavailable)
        }
        let clock = ContinuousClock()
        let started = clock.now
        guard let answer = await InsightSummarizer.summary(for: request, service: service, timeout: timeout) else {
            return InsightResponsePayload(requestID: id, failure: clock.now - started >= timeout ? .timeout : .refused)
        }
        return InsightResponsePayload(requestID: id, answer: answer)
    }
}
