import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Dashboard brief (#453)

@Suite("ChangeBriefViewModel")
@MainActor
struct ChangeBriefViewModelTests {
    let events = NetworkEventService()
    let counts = ChangeDigestCounts(found: 4, notFound: 0)
    static let answer = "Two new devices appeared on the network."

    func makeViewModel(_ insight: MockInsightService) -> ChangeBriefViewModel {
        ChangeBriefViewModel(service: insight, eventService: events)
    }

    func logJoin(_ name: String) {
        events.log(type: .deviceJoined, title: "Device Joined: \(name)", details: nil, severity: .success)
    }

    /// Starts a refresh, answers the `index`th request with `update`, and waits for it.
    func refreshAnswering(_ viewModel: ChangeBriefViewModel, _ insight: MockInsightService, with update: InsightUpdate, index: Int = 0) async {
        let task = Task { await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false) }
        await waitUntil { insight.requests.count > index }
        insight.send(update, to: index)
        await task.value
    }

    @Test func aChangeShowsTheKeyPointsAndTheModelText() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        logJoin("Speaker")

        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        #expect(viewModel.brief == ChangeSummary(keyPoints: ["2 devices joined the network."], text: Self.answer))
        #expect(insight.requests.first?.subject == "Network changes in the last 24 hours")
    }

    @Test func reappearingWithNothingNewDoesNotAskAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        await refreshAnswering(viewModel, insight, with: .finished("A camera joined the network."))

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)

        #expect(insight.requests.count == 1)
        #expect(viewModel.brief?.text == "A camera joined the network.")
    }

    @Test func reappearingWhileTheFirstRequestRunsDoesNotAskAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        let first = Task { await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false) }
        await waitUntil { insight.requests.count == 1 }

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)
        insight.send(.finished("A camera joined the network."))
        await first.value

        #expect(insight.requests.count == 1)
        #expect(viewModel.brief?.text == "A camera joined the network.")
    }

    @Test func aNewEventAsksAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        await refreshAnswering(viewModel, insight, with: .finished("A camera joined the network."))
        logJoin("Speaker")

        await refreshAnswering(viewModel, insight, with: .finished(Self.answer), index: 1)

        #expect(insight.requests.count == 2)
        #expect(viewModel.brief?.keyPoints == ["2 devices joined the network."])
    }

    @Test func nothingIsAskedDuringAScan() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: true)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func anUnavailableModelIsNotAskedAndShowsNothing() async {
        let insight = MockInsightService(isAvailable: false)
        let viewModel = makeViewModel(insight)
        logJoin("Camera")

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func aFailedAnswerShowsNothingAndIsNotRetriedOnReappear() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        await refreshAnswering(viewModel, insight, with: .failed)

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)

        #expect(viewModel.brief == nil)
        #expect(insight.requests.count == 1)
    }

    @Test func aRequestCancelledByLeavingTheDashboardIsAskedAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        let first = Task { await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false) }
        await waitUntil { insight.requests.count == 1 }
        first.cancel()
        await first.value

        await refreshAnswering(viewModel, insight, with: .finished("A camera joined the network."), index: 1)

        #expect(insight.requests.count == 2)
        #expect(viewModel.brief?.text == "A camera joined the network.")
    }

    @Test func aNewSpeedTestAsksAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let earlier = SpeedTestResult(downloadSpeed: 300, uploadSpeed: 20, latency: 12)
        earlier.timestamp = Date().addingTimeInterval(-3600)
        let first = Task { await viewModel.refresh(deviceNames: [:], speedTests: [earlier], counts: counts, isScanning: false) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("The download speed was 300 Mbps."))
        await first.value
        let latest = SpeedTestResult(downloadSpeed: 80, uploadSpeed: 10, latency: 12)

        let second = Task { await viewModel.refresh(deviceNames: [:], speedTests: [latest, earlier], counts: counts, isScanning: false) }
        await waitUntil { insight.requests.count == 2 }
        insight.send(.finished("The download speed fell."), to: 1)
        await second.value

        #expect(insight.requests.count == 2)
    }

    @Test func noChangesAsksNothing() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(type: .scanComplete, title: "Scan Complete — 4 devices found", details: nil, severity: .info)

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func eventsOlderThanADayAreLeftOut() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(NetworkEvent(type: .deviceJoined, timestamp: Date().addingTimeInterval(-90_000), title: "Device Joined: Old"))

        await viewModel.refresh(deviceNames: [:], speedTests: [], counts: counts, isScanning: false)

        #expect(insight.requests.isEmpty)
    }
}

// MARK: - Timeline day summary (#453)

@Suite("TimelineViewModel summaries")
@MainActor
struct TimelineSummaryTests {
    let events = NetworkEventService()

    func makeViewModel(_ insight: MockInsightService, isScanning: Bool = false) -> TimelineViewModel {
        let viewModel = TimelineViewModel(service: events, insightService: insight, isScanning: { isScanning })
        events.log(type: .deviceJoined, title: "Device Joined: Camera", details: "192.168.1.50", severity: .success)
        events.log(type: .deviceLeft, title: "Device Left: 192.168.1.30", details: nil, severity: .warning)
        viewModel.load()
        return viewModel
    }

    @Test func summarizingADayShowsProgressThenTheText() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let task = Task { await viewModel.summarize("Today") }
        await waitUntil { insight.requests.count == 1 }
        #expect(viewModel.summary(for: "Today") == .loading)

        insight.send(.finished("A camera joined and a device left."))
        await task.value

        #expect(viewModel.summary(for: "Today") == .finished(ChangeSummary(
            keyPoints: ["1 device joined the network.", "1 device left the network."],
            text: "A camera joined and a device left."
        )))
    }

    @Test func theSummaryRespectsTheTypeFilter() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        viewModel.applyFilter(.deviceLeft)
        let task = Task { await viewModel.summarize("Today") }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A device left."))
        await task.value

        #expect(insight.requests.first?.facts == ["Devices left: 1", "Left: 192.168.1.30"])
        #expect(insight.requests.first?.subject.hasPrefix("Device Left events on ") == true)
    }

    @Test func changingTheFilterDropsTheSummary() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let task = Task { await viewModel.summarize("Today") }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A camera joined and a device left."))
        await task.value

        viewModel.applyFilter(.deviceLeft)

        #expect(viewModel.summary(for: "Today") == nil)
    }

    @Test func aFailedAnswerSaysTheSummaryIsUnavailable() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let task = Task { await viewModel.summarize("Today") }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.failed)
        await task.value

        #expect(viewModel.summary(for: "Today") == .unavailable)
    }

    @Test func theActionIsHiddenWhenTheModelIsUnavailable() {
        #expect(!makeViewModel(MockInsightService(isAvailable: false)).canSummarize)
        #expect(makeViewModel(MockInsightService()).canSummarize)
    }

    @Test func nothingIsAskedDuringAScan() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight, isScanning: true)

        await viewModel.summarize("Today")

        #expect(insight.requests.isEmpty)
        #expect(viewModel.summary(for: "Today") == .unavailable)
    }
}
