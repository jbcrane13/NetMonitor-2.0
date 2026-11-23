import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

// MARK: - Dashboard brief (#453)

@Suite("ChangeBriefViewModel")
@MainActor
struct ChangeBriefViewModelTests {
    let events = NetworkEventService()
    static let answer = "Two new devices appeared on the network."

    func makeViewModel(_ insight: MockInsightService) -> ChangeBriefViewModel {
        ChangeBriefViewModel(service: insight, eventService: events)
    }

    func logJoin(_ name: String) {
        events.log(type: .deviceJoined, title: "Device Joined: \(name)", details: nil, severity: .success)
    }

    /// Starts a refresh, answers the `index`th request with `update`, and waits for it.
    func refreshAnswering(_ viewModel: ChangeBriefViewModel, _ insight: MockInsightService, with update: InsightUpdate, index: Int = 0) async {
        let task = Task { await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false) }
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

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)

        #expect(insight.requests.count == 1)
        #expect(viewModel.brief?.text == "A camera joined the network.")
    }

    @Test func reappearingWhileTheFirstRequestRunsDoesNotAskAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        let first = Task { await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false) }
        await waitUntil { insight.requests.count == 1 }

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)
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

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: true)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func anUnavailableModelIsNotAskedAndShowsNothing() async {
        let insight = MockInsightService(isAvailable: false)
        let viewModel = makeViewModel(insight)
        logJoin("Camera")

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func aFailedAnswerShowsNothingAndIsNotRetriedOnReappear() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        await refreshAnswering(viewModel, insight, with: .failed)

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)

        #expect(viewModel.brief == nil)
        #expect(insight.requests.count == 1)
    }

    @Test func aRequestCancelledByLeavingTheDashboardIsAskedAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("Camera")
        let first = Task { await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false) }
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
        let first = Task { await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [earlier], isScanning: false) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("The download speed was 300 Mbps."))
        await first.value
        let latest = SpeedTestResult(downloadSpeed: 80, uploadSpeed: 10, latency: 12)

        let second = Task { await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [latest, earlier], isScanning: false) }
        await waitUntil { insight.requests.count == 2 }
        insight.send(.finished("The download speed fell."), to: 1)
        await second.value

        #expect(insight.requests.count == 2)
    }

    @Test func noChangesAsksNothing() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(type: .scanComplete, title: "Scan Complete — 4 devices found", details: nil, severity: .info)

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func eventsOlderThanADayAreLeftOut() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(NetworkEvent(type: .deviceJoined, timestamp: Date().addingTimeInterval(-90_000), title: "Device Joined: Old"))

        await viewModel.refresh(scanned: [], saved: [], networkProfileID: nil, speedTests: [], isScanning: false)

        #expect(insight.requests.isEmpty)
    }

    @Test func namesAndCountsComeFromTheActiveNetworksSavedDevices() async throws {
        let home = UUID()
        let saved = [
            LocalDevice(ipAddress: "192.168.1.50", macAddress: "AA:BB:CC:00:00:50", customName: "Garage Camera", networkProfileID: home),
            LocalDevice(ipAddress: "192.168.1.30", macAddress: "AA:BB:CC:00:00:30", customName: "Office Printer", networkProfileID: home),
            LocalDevice(ipAddress: "10.0.0.9", macAddress: "AA:BB:CC:00:00:09", customName: "Cabin TV", networkProfileID: UUID())
        ]
        let scanned = [
            DiscoveredDevice(ipAddress: "192.168.1.50", latency: 3, discoveredAt: Date(), networkProfileID: home),
            DiscoveredDevice(
                ipAddress: "192.168.1.30", hostname: nil, vendor: nil, macAddress: nil, latency: nil,
                discoveredAt: Date(), source: .local, networkProfileID: home, isCached: true
            )
        ]
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(type: .deviceJoined, title: "Device Joined: Camera", details: "192.168.1.50", severity: .success)

        let task = Task { await viewModel.refresh(scanned: scanned, saved: saved, networkProfileID: home, speedTests: [], isScanning: false) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished("A camera joined the network."))
        await task.value

        let request = try #require(insight.requests.first)
        #expect(request.facts == [
            "Devices joined: 1",
            "Joined: Garage Camera",
            "Devices found by the last scan: 1",
            "Saved devices not found by the last scan: 1"
        ])
    }
}
