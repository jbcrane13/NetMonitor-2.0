import Foundation
import NetMonitorCore
import SwiftData

/// The Mac dashboard's "since yesterday" brief (#491 S6): what changed on the local network in
/// the last 24 hours, worded by the on-device model from `ChangeDigestBuilder`'s digest. iOS's
/// `ChangeBriefViewModel` is the reference; both ask through `ChangeBriefState`.
///
/// The model is asked at most once per digest, never during a scan, and the card hides when the
/// model is unavailable, its answer fails, or nothing changed.
@MainActor
@Observable
final class ChangeBriefMacViewModel {
    /// The digest covers this much time before now.
    static let window: TimeInterval = 24 * 60 * 60

    /// The dashboard's brief. Shared so that a dashboard rebuilt by navigation keeps its cache;
    /// `configureForUITests(arguments:)` replaces it under `--uitesting`.
    private(set) static var dashboard = ChangeBriefMacViewModel(
        service: InsightService.shared,
        eventService: NetworkEventService.shared,
        speedTests: { MacSpeedTestHistory.store.entries() }
    )

    /// The brief to show, or nil when the card is hidden.
    var brief: ChangeSummary? { state.brief }

    private let state: ChangeBriefState
    private let eventService: any NetworkEventServiceProtocol
    private let speedTests: @MainActor () -> [SpeedTestHistoryEntry]
    private let now: @MainActor () -> Date

    init(
        service: any InsightServiceProtocol,
        eventService: any NetworkEventServiceProtocol,
        speedTests: @escaping @MainActor () -> [SpeedTestHistoryEntry],
        timeout: Duration = ChangeBriefState.timeout,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        state = ChangeBriefState(service: service, timeout: timeout)
        self.eventService = eventService
        self.speedTests = speedTests
        self.now = now
    }

    /// Asks the model about the last day's changes on `networkProfileID` when the digest differs
    /// from the last one.
    /// - Parameter devices: the saved devices; those of the network (or of none) name devices
    ///   and count as found (online after the last scan) or not found.
    func refresh(devices: [LocalDevice], networkProfileID: UUID?, isScanning: Bool) async {
        // Another network's brief never stays on screen, even while a scan holds back the new one.
        state.keepOnly(network: networkProfileID)
        guard !isScanning else { return }
        guard state.isAvailable else {
            state.hide()
            return
        }
        let network = devices.filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
        let found = network.count { $0.status == .online }
        let end = now()
        let start = end.addingTimeInterval(-Self.window)
        // Events with no network predate network IDs; like iOS, they still count.
        let events = eventService.events(from: start, to: end)
            .filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
        let request = ChangeDigestBuilder.request(
            events: events,
            from: start,
            to: end,
            deviceNames: ChangeDigestBuilder.deviceNames(network),
            deviceNamesByID: ChangeDigestBuilder.deviceNamesByID(network),
            speedTests: Self.latestTwo(speedTests()),
            counts: ChangeDigestCounts(found: found, notFound: network.count - found)
        )
        await state.ask(request, network: networkProfileID)
    }

    /// The saved devices the brief of `profileID` names and counts: that network's rows and
    /// unassigned ones, every one of them. Read from the store, not the scan coordinator, whose
    /// devices are whichever network it scanned last.
    static func savedDevices(for profileID: UUID, in context: ModelContext) -> [LocalDevice] {
        let id: UUID? = profileID
        let descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate<LocalDevice> { device in
                device.networkProfileID == id || device.networkProfileID == nil
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The two most recent saved tests, as the digest compares them.
    private static func latestTwo(_ entries: [SpeedTestHistoryEntry]) -> [SpeedTestResult] {
        entries.sorted { $0.timestamp > $1.timestamp }.prefix(2).map { entry in
            let result = SpeedTestResult(downloadSpeed: entry.downloadMbps, uploadSpeed: entry.uploadMbps, latency: entry.pingMs)
            result.timestamp = entry.timestamp
            return result
        }
    }

    // MARK: - UI tests

    /// States no number and names nothing, so it passes `InsightSummarizer`'s checks for any digest.
    static let uiTestAnswer = "The app recorded changes on this network in the last day; the key points above say what changed."

    /// `--uitest-insight=answer` answers every request with `uiTestAnswer`; `=unavailable` is never
    /// available. Otherwise the on-device model.
    static func uiTestInsightService(arguments: [String]) -> any InsightServiceProtocol {
        switch arguments.first(where: { $0.hasPrefix("--uitest-insight=") })?.dropFirst("--uitest-insight=".count) {
        case "answer": FixedAnswerInsightService(answer: uiTestAnswer)
        case "unavailable": UnavailableInsightService()
        default: InsightService.shared
        }
    }

    /// Under `--uitesting`: the insight service from `--uitest-insight`, and no saved speed tests,
    /// which are the user's own and not isolated like the history files.
    static func configureForUITests(arguments: [String]) {
        dashboard = ChangeBriefMacViewModel(
            service: uiTestInsightService(arguments: arguments),
            eventService: NetworkEventService.shared,
            speedTests: { [] }
        )
    }
}
