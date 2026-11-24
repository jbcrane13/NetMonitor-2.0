import Foundation

/// Collects one finished answer from the insight service, for places that show a summary
/// whole rather than as it streams: a report page, a notification (#453).
public enum InsightSummarizer {
    /// The model's answer to `request`, or nil when it can't be used: the model is
    /// unavailable, fails, answers with nothing or with a cut-off sentence, takes longer than
    /// `timeout`, states a number that isn't in the request (`InsightGrounding`), or contains a
    /// link, email address, phone number or unstated domain (`InsightTextFilter`). Callers
    /// omit the summary on nil. A timed-out answer is cancelled. The wait is exactly `timeout`,
    /// even through a Mac: notification bodies keep to their budget.
    public static func summary(
        for request: InsightRequest,
        service: any InsightServiceProtocol,
        timeout: Duration
    ) async -> String? {
        await outcome(for: request, service: service, timeout: timeout, waitsForMac: false).answer?.text
    }

    /// Like `summary`, but says whether a missing answer is lasting or for now, and who wrote
    /// the answer (#457). Callers that remember outcomes ask again after `.tryLater`.
    ///
    /// Through a Mac the wait is at least `macWait`, past the Mac's own limit plus the round
    /// trip, unless `waitsForMac` is false.
    public static func outcome(
        for request: InsightRequest,
        service: any InsightServiceProtocol,
        timeout: Duration,
        waitsForMac: Bool = true
    ) async -> InsightOutcome {
        guard service.isAvailable else { return .tryLater }
        let source = InsightService.source(of: service)
        let wait = source == .mac && waitsForMac ? max(timeout, macWait) : timeout
        let update = await withTaskGroup(of: InsightUpdate?.self) { group in
            group.addTask {
                for await update in service.explain(request) {
                    if case .partial = update {
                        continue
                    }
                    return update
                }
                return .failed
            }
            group.addTask {
                try? await Task.sleep(for: wait)
                return nil
            }
            // Whichever ends first decides; cancelling ends the other, and a cancelled
            // stream stops the model.
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
        switch update {
        case nil, .unreachable?: return .tryLater
        case .failed?, .partial?: return .refused
        case let .finished(answer)?:
            // An answer cut off by the token cap ends mid-sentence; it is dropped like any other.
            let text = usable(answer, for: request.kind)
            guard let last = text.last, ".!?".contains(last),
                  InsightGrounding.isGrounded(text, in: request),
                  InsightTextFilter.isClean(text, in: request)
            else {
                return .refused
            }
            return .answer(InsightAnswer(text: text, source: source))
        }
    }

    /// How long a request through a Mac may take: the phone client's limit, which is past the
    /// Mac's 20 s, plus time for its reply.
    public static let macWait: Duration = CompanionInsightClient.defaultTimeout + .seconds(2)

    /// The part of `answer` that is checked and used. A notification body is one line: the
    /// model sometimes goes on to recite its facts on further lines, and those are dropped.
    static func usable(_ answer: String, for kind: InsightRequest.Kind) -> String {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .notification, let firstLine = text.split(whereSeparator: \.isNewline).first {
            text = firstLine.trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}

/// A checked answer and who wrote it (#457).
public struct InsightAnswer: Sendable, Equatable {
    public let text: String
    public let source: InsightSource

    public init(text: String, source: InsightSource) {
        self.text = text
        self.source = source
    }
}

/// What came of asking for a summary (#457).
public enum InsightOutcome: Sendable, Equatable {
    case answer(InsightAnswer)
    /// The model answered nothing usable for this request; asking again gets the same.
    case refused
    /// The model couldn't be reached or didn't answer in time: ask again later.
    case tryLater

    public var answer: InsightAnswer? {
        if case let .answer(answer) = self {
            return answer
        }
        return nil
    }
}
