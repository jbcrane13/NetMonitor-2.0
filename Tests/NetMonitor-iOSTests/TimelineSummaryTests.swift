import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

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
        let task = Task { await viewModel.summarize("Today", savedDevices: [], speedTests: []) }
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
        let task = Task { await viewModel.summarize("Today", savedDevices: [], speedTests: []) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A device left."))
        await task.value

        #expect(insight.requests.first?.facts == ["Devices left: 1", "Left: 192.168.1.30"])
        #expect(insight.requests.first?.subject.hasPrefix("Device Left events on ") == true)
    }

    @Test func changingTheFilterDropsTheSummary() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let task = Task { await viewModel.summarize("Today", savedDevices: [], speedTests: []) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A camera joined and a device left."))
        await task.value

        viewModel.applyFilter(.deviceLeft)

        #expect(viewModel.summary(for: "Today") == nil)
    }

    @Test func aFailedAnswerSaysTheSummaryIsUnavailable() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let task = Task { await viewModel.summarize("Today", savedDevices: [], speedTests: []) }
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

        await viewModel.summarize("Today", savedDevices: [], speedTests: [])

        #expect(insight.requests.isEmpty)
        #expect(viewModel.summary(for: "Today") == .unavailable)
    }

    @Test func theSummaryNamesSavedDevicesAndComparesSpeedTests() async throws {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        let saved = [LocalDevice(ipAddress: "192.168.1.30", macAddress: "AA:BB:CC:00:00:30", customName: "Office Printer")]
        let earlier = SpeedTestResult(downloadSpeed: 300, uploadSpeed: 20, latency: 12)
        earlier.timestamp = Date().addingTimeInterval(-3 * 86_400)
        let latest = SpeedTestResult(downloadSpeed: 80, uploadSpeed: 10, latency: 12)
        let task = Task { await viewModel.summarize("Today", savedDevices: saved, speedTests: [latest, earlier]) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A device left and the download speed fell."))
        await task.value

        let request = try #require(insight.requests.first)
        #expect(request.facts.contains("Left: Office Printer"))
        #expect(request.facts.contains("Latest download: 80.0 Mbps"))
        #expect(request.facts.contains("Previous download: 300.0 Mbps"))
    }

    @Test func theActionIsHiddenForRoutineEventFilters() {
        let viewModel = makeViewModel(MockInsightService())
        viewModel.applyFilter(.scanComplete)
        #expect(!viewModel.canSummarize)
        viewModel.applyFilter(.toolRun)
        #expect(!viewModel.canSummarize)
        viewModel.applyFilter(.deviceLeft)
        #expect(viewModel.canSummarize)
    }
}
