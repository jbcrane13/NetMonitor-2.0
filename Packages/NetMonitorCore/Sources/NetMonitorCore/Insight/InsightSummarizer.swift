import Foundation

/// Collects one finished answer from the insight service, for places that show a summary
/// whole rather than as it streams: a report page, a notification (#453).
public enum InsightSummarizer {
    /// The model's answer to `request`, or nil when it can't be used: the model is
    /// unavailable, fails, answers with nothing or with a cut-off sentence, takes longer than
    /// `timeout`, or states a number that isn't in the request (`InsightGrounding`). Callers
    /// omit the summary on nil.
    /// A timed-out answer is cancelled.
    public static func summary(
        for request: InsightRequest,
        service: any InsightServiceProtocol,
        timeout: Duration
    ) async -> String? {
        guard service.isAvailable else { return nil }
        let answer = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await update in service.explain(request) {
                    switch update {
                    case .partial: continue
                    case let .finished(text): return text
                    case .failed: return nil
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            // Whichever ends first decides; cancelling ends the other, and a cancelled
            // stream stops the model.
            let first = await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
        // An answer cut off by the token cap ends mid-sentence; it is dropped like any other.
        guard let text = answer?.trimmingCharacters(in: .whitespacesAndNewlines),
              let last = text.last, ".!?".contains(last),
              InsightGrounding.isGrounded(text, in: request)
        else {
            return nil
        }
        return text
    }
}
