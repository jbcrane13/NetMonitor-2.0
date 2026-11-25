import Foundation
import NetMonitorCore
import NetworkScanKit

/// The dashboard's "since yesterday" brief (#453): what changed in the last 24 hours, worded
/// by the on-device model from `ChangeDigestBuilder`'s digest.
///
/// The model is asked at most once per digest (`ChangeBriefState`, shared with the Mac). Re-appearing
/// with the same events, names, speed tests and counts reuses the last outcome, including a failed
/// one, and a request already running is not sent again. Nothing is asked during a scan.
@MainActor
@Observable
final class ChangeBriefViewModel {
    /// The brief to show, or nil when the card is hidden: nothing changed, the model is
    /// unavailable, or its answer failed `InsightSummarizer`'s checks.
    var brief: ChangeSummary? { state.brief }

    /// The digest covers this much time before now.
    static let window: TimeInterval = 24 * 60 * 60
    /// Not on a critical path, so the model gets nearly as long as the PDF summary's 20 s.
    static let timeout = ChangeBriefState.timeout

    /// The dashboard's brief. Shared so that a dashboard rebuilt by navigation keeps its cache.
    static let dashboard = ChangeBriefViewModel(
        service: UITestBootstrap.insightService ?? PhoneInsight.shared,
        eventService: NetworkEventService.shared
    )

    private let state: ChangeBriefState
    private let eventService: any NetworkEventServiceProtocol
    private let now: @MainActor () -> Date

    init(
        service: any InsightServiceProtocol,
        eventService: any NetworkEventServiceProtocol,
        timeout: Duration = ChangeBriefViewModel.timeout,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        state = ChangeBriefState(service: service, timeout: timeout)
        self.eventService = eventService
        self.now = now
    }

    /// Asks the model about the last day's changes when the digest differs from the last one.
    /// - Parameters:
    ///   - scanned: the dashboard's devices; cached ones did not answer the last scan.
    ///   - saved: every saved device. Only those of the network being shown (or of none) name
    ///     devices and count as found or missing.
    ///   - networkProfileID: the network being shown.
    ///   - speedTests: the most recent saved speed tests; the latest two are enough.
    func refresh(
        scanned: [DiscoveredDevice],
        saved: [LocalDevice],
        networkProfileID: UUID?,
        speedTests: [SpeedTestResult],
        isScanning: Bool
    ) async {
        // Another network's brief never stays on screen, even while a scan holds back the new one.
        state.keepOnly(network: networkProfileID)
        guard !isScanning else { return }
        guard state.isAvailable else {
            state.hide()
            return
        }
        let found = Set(scanned.filter { !$0.isCached }.map(\.ipAddress))
        // Saved rows of other networks are neither found nor missing here.
        let network = saved.filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
        let end = now()
        let request = ChangeDigestBuilder.request(
            events: eventService.events(from: end.addingTimeInterval(-Self.window), to: end),
            from: end.addingTimeInterval(-Self.window),
            to: end,
            deviceNames: ChangeDigestBuilder.deviceNames(network),
            speedTests: speedTests,
            counts: ChangeDigestCounts(found: found.count, notFound: network.count { !found.contains($0.ipAddress) })
        )
        await state.ask(request, network: networkProfileID)
    }
}
