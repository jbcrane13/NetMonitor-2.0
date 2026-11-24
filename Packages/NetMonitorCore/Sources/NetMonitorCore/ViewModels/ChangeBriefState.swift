import Foundation
import Observation

/// A summary written by the on-device model with the app's own key points, which are shown
/// word for word beside it (#453).
public struct ChangeSummary: Equatable, Sendable {
    public let keyPoints: [String]
    public let text: String
    /// Who wrote `text`: this device or the connected Mac (#457).
    public let source: InsightSource

    public init(keyPoints: [String], text: String, source: InsightSource = .device) {
        self.keyPoints = keyPoints
        self.text = text
        self.source = source
    }
}

/// Asks the model about a "since yesterday" digest at most once (#453, #491 S6). Both apps'
/// dashboard briefs use it; each builds its own digest.
///
/// Asking again about the same digest reuses the last outcome, including a failed one, and
/// a request already running is not sent again. A cancelled ask is not an answer, so the
/// next ask about that digest goes to the model. A brief never outlives its digest: asking
/// about a different one hides it until the new answer, and so does showing another network.
@MainActor
@Observable
public final class ChangeBriefState {
    /// The brief to show, or nil when the card is hidden: nothing changed, the model is
    /// unavailable, or its answer failed `InsightSummarizer`'s checks.
    public private(set) var brief: ChangeSummary?

    /// Not on a critical path, so the model gets nearly as long as the PDF summary's 20 s.
    public static let timeout: Duration = .seconds(15)

    private let service: any InsightServiceProtocol
    private let timeout: Duration
    /// The digest last asked about, or being asked about; `.some(nil)` when there was none.
    private var lastRequest: InsightRequest??
    /// The network the shown brief describes.
    private var briefNetwork: UUID?

    public init(service: any InsightServiceProtocol, timeout: Duration = ChangeBriefState.timeout) {
        self.service = service
        self.timeout = timeout
    }

    public var isAvailable: Bool { service.isAvailable }

    /// Hides the brief, keeping what was asked: the model became unavailable.
    public func hide() {
        brief = nil
    }

    /// Hides a brief about any network but `network`, such as while a scan of a newly joined
    /// network runs and nothing is asked.
    public func keepOnly(network: UUID?) {
        if brief != nil, briefNetwork != network {
            brief = nil
        }
    }

    /// Asks about `request`, the digest of `network`, unless it is the digest last asked about.
    /// A different digest hides the shown brief at once; nil leaves it hidden.
    public func ask(_ request: InsightRequest?, network: UUID? = nil) async {
        guard lastRequest != .some(request) else { return }
        lastRequest = .some(request)
        brief = nil
        guard let request else { return }
        let source = InsightService.source(of: service)
        let text = await InsightSummarizer.summary(for: request, service: service, timeout: timeout)
        // Leaving the dashboard cancels its task; that is not an answer, so ask again next time.
        if Task.isCancelled {
            if lastRequest == .some(request) {
                lastRequest = nil
            }
            return
        }
        // A newer digest was asked about meanwhile; its answer decides.
        guard lastRequest == .some(request) else { return }
        brief = text.map { ChangeSummary(keyPoints: request.observations, text: $0, source: source) }
        briefNetwork = network
    }
}
