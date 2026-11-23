import Foundation
import NetMonitorCore

/// A summary written by the on-device model with the app's own key points, which are shown
/// word for word beside it (#453).
struct ChangeSummary: Equatable {
    let keyPoints: [String]
    let text: String
}

/// The dashboard's "since yesterday" brief (#453): what changed in the last 24 hours, worded
/// by the on-device model from `ChangeDigestBuilder`'s digest.
///
/// The model is asked at most once per digest. Re-appearing with the same events, names,
/// speed tests and counts reuses the last outcome, including a failed one, and a request
/// already running is not sent again. Nothing is asked during a scan.
@MainActor
@Observable
final class ChangeBriefViewModel {
    /// The brief to show, or nil when the card is hidden: nothing changed, the model is
    /// unavailable, or its answer failed `InsightSummarizer`'s checks.
    private(set) var brief: ChangeSummary?

    /// The digest covers this much time before now.
    static let window: TimeInterval = 24 * 60 * 60
    /// Not on a critical path, so the model gets nearly as long as the PDF summary's 20 s.
    static let timeout: Duration = .seconds(15)

    /// The dashboard's brief. Shared so that a dashboard rebuilt by navigation keeps its cache.
    static let dashboard: ChangeBriefViewModel = {
        // The dashboard can ask before the app's launch hook seeds UI-test events.
        UITestBootstrap.seedEventsIfNeeded()
        return ChangeBriefViewModel(service: UITestBootstrap.insightService ?? InsightService.shared, eventService: NetworkEventService.shared)
    }()

    private let service: any InsightServiceProtocol
    private let eventService: any NetworkEventServiceProtocol
    private let timeout: Duration
    private let now: @MainActor () -> Date
    /// The digest last asked about, or being asked about; `.some(nil)` when there was none.
    private var lastRequest: InsightRequest??

    init(
        service: any InsightServiceProtocol,
        eventService: any NetworkEventServiceProtocol,
        timeout: Duration = ChangeBriefViewModel.timeout,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.service = service
        self.eventService = eventService
        self.timeout = timeout
        self.now = now
    }

    /// Asks the model about the last day's changes when the digest differs from the last one.
    /// - Parameters:
    ///   - deviceNames: saved devices' display names by IP address.
    ///   - speedTests: the most recent saved speed tests; the latest two are enough.
    func refresh(deviceNames: [String: String], speedTests: [SpeedTestResult], counts: ChangeDigestCounts, isScanning: Bool) async {
        guard !isScanning else { return }
        guard service.isAvailable else {
            brief = nil
            return
        }
        let end = now()
        let request = ChangeDigestBuilder.request(
            events: eventService.events(from: end.addingTimeInterval(-Self.window), to: end),
            from: end.addingTimeInterval(-Self.window),
            to: end,
            deviceNames: deviceNames,
            speedTests: speedTests,
            counts: counts
        )
        guard lastRequest != .some(request) else { return }
        lastRequest = .some(request)
        guard let request else {
            brief = nil
            return
        }
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
        brief = text.map { ChangeSummary(keyPoints: request.observations, text: $0) }
    }
}
