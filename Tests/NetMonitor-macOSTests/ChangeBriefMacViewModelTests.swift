import Testing
import Foundation
import NetMonitorCore
import SwiftData
@testable import NetMonitor_macOS

// MARK: - Dashboard brief (#491 S6)

@Suite("ChangeBriefMacViewModel")
@MainActor
struct ChangeBriefMacViewModelTests {
    /// 2026-11-22 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_795_348_800)
    let home = UUID()
    /// No scan recorded: no device is a past one unless unseen for a week before now.
    let noScans = PresenceSnapshot(lastScans: [:], now: Date())
    let events = NetworkEventService()
    static let answer = "A device joined the network."

    func makeViewModel(_ insight: any InsightServiceProtocol, speedTests: [SpeedTestHistoryEntry] = []) -> ChangeBriefMacViewModel {
        let now = now
        return ChangeBriefMacViewModel(service: insight, eventService: events, speedTests: { speedTests }, now: { now })
    }

    func logJoin(_ name: String, profileID: UUID?, ip: String = "192.168.77.20", secondsAgo: TimeInterval = 600, deviceID: UUID? = nil) {
        events.log(NetworkEvent(
            type: .deviceJoined, timestamp: now.addingTimeInterval(-secondsAgo), title: "Device Joined: \(name)",
            details: ip, severity: .success, deviceID: deviceID, networkProfileID: profileID
        ))
    }

    /// Starts a refresh, answers the `index`th request with `update`, and waits for it.
    func refreshAnswering(
        _ viewModel: ChangeBriefMacViewModel, _ insight: MockInsightService, devices: [LocalDevice] = [],
        with update: InsightUpdate, index: Int = 0
    ) async {
        let task = Task { await viewModel.refresh(devices: devices, networkProfileID: home, presence: noScans, isScanning: false) }
        await waitUntil { insight.requests.count > index }
        insight.send(update, to: index)
        await task.value
    }

    // MARK: - Showing

    @Test func aChangeShowsTheKeyPointsAndTheModelText() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        #expect(viewModel.brief == ChangeSummary(keyPoints: ["1 device joined the network."], text: Self.answer))
        #expect(insight.requests.first?.subject == "Network changes in the last 24 hours")
    }

    @Test func devicesAreNamedByTheirSavedRowsCurrentName() async throws {
        let printer = LocalDevice(ipAddress: "192.168.77.20", macAddress: "00:1B:A9:77:00:20", customName: "Office Printer",
                                  status: .online, networkProfileID: home)
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home, deviceID: printer.id)

        await refreshAnswering(viewModel, insight, devices: [printer], with: .finished(Self.answer))

        let request = try #require(insight.requests.first)
        #expect(request.facts.contains("Joined: Office Printer"))
        #expect(!request.facts.contains("Joined: uitest-printer"))
    }

    @Test func countsComeFromTheNetworksSavedDevices() async throws {
        let rows = [
            LocalDevice(ipAddress: "192.168.77.20", macAddress: "00:1B:A9:77:00:20", status: .online, networkProfileID: home),
            LocalDevice(ipAddress: "192.168.77.21", macAddress: "00:1B:A9:77:00:21", status: .offline, networkProfileID: home),
            LocalDevice(ipAddress: "10.0.0.9", macAddress: "00:1B:A9:77:00:09", status: .online, networkProfileID: UUID())
        ]
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await refreshAnswering(viewModel, insight, devices: rows, with: .finished(Self.answer))

        let request = try #require(insight.requests.first)
        #expect(request.facts.suffix(2) == ["Devices found by the last scan: 1", "Saved devices not found by the last scan: 1"])
    }

    /// #583: a device unseen for a month is a past device, not one the last scan didn't find.
    @Test func pastDevicesAreNotCountedAsNotFound() async throws {
        let old = LocalDevice(ipAddress: "192.168.77.22", macAddress: "00:1B:A9:77:00:22", status: .offline, networkProfileID: home)
        old.lastSeen = Date().addingTimeInterval(-30 * 86_400)
        let rows = [
            LocalDevice(ipAddress: "192.168.77.20", macAddress: "00:1B:A9:77:00:20", status: .online, networkProfileID: home),
            LocalDevice(ipAddress: "192.168.77.21", macAddress: "00:1B:A9:77:00:21", status: .offline, networkProfileID: home),
            old
        ]
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await refreshAnswering(viewModel, insight, devices: rows, with: .finished(Self.answer))

        let request = try #require(insight.requests.first)
        #expect(request.facts.suffix(2) == ["Devices found by the last scan: 1", "Saved devices not found by the last scan: 1"])
    }

    @Test func theLatestTwoSavedSpeedTestsAreCompared() async throws {
        let tests = [
            SpeedTestHistoryEntry(timestamp: now.addingTimeInterval(-3 * 86_400), downloadMbps: 500, uploadMbps: 50, pingMs: 9),
            SpeedTestHistoryEntry(timestamp: now.addingTimeInterval(-3600), downloadMbps: 80, uploadMbps: 10, pingMs: 12),
            SpeedTestHistoryEntry(timestamp: now.addingTimeInterval(-2 * 86_400), downloadMbps: 300, uploadMbps: 20, pingMs: 11)
        ]
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight, speedTests: tests)

        await refreshAnswering(viewModel, insight, with: .finished("The download speed fell."))

        let request = try #require(insight.requests.first)
        #expect(request.facts.prefix(4) == [
            "Latest download: 80.0 Mbps", "Latest upload: 10.0 Mbps", "Previous download: 300.0 Mbps", "Previous upload: 20.0 Mbps"
        ])
    }

    // MARK: - Caching

    @Test func reappearingWithNothingNewDoesNotAskAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)
        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false)

        #expect(insight.requests.count == 1)
        #expect(viewModel.brief?.text == Self.answer)
    }

    @Test func aNewEventAsksAgain() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)
        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))
        logJoin("uitest-camera", profileID: home, ip: "192.168.77.21", secondsAgo: 60)

        await refreshAnswering(viewModel, insight, with: .finished("Two devices joined the network."), index: 1)

        #expect(viewModel.brief?.keyPoints == ["2 devices joined the network."])
    }

    // MARK: - Hidden

    @Test func anotherNetworksBriefIsHiddenEvenDuringAScan() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)
        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        await viewModel.refresh(devices: [], networkProfileID: UUID(), presence: noScans, isScanning: true)

        #expect(viewModel.brief == nil)
    }

    @Test func aNewDigestHidesTheOldBriefUntilItIsAnswered() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)
        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))
        logJoin("uitest-camera", profileID: home, ip: "192.168.77.21", secondsAgo: 60)

        let second = Task { await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false) }
        await waitUntil { insight.requests.count == 2 }
        #expect(viewModel.brief == nil)
        insight.send(.finished("Two devices joined the network."), to: 1)
        await second.value
        #expect(viewModel.brief?.text == "Two devices joined the network.")
    }

    @Test func devicesBackOnlineAreNotCountedAsJoins() async throws {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(NetworkEvent(
            type: .deviceJoined, timestamp: now.addingTimeInterval(-60), title: "Device Back Online: uitest-device",
            details: "192.168.77.77", severity: .success, networkProfileID: home
        ))

        await refreshAnswering(viewModel, insight, with: .finished("A device came back online."))

        #expect(viewModel.brief?.keyPoints == ["1 device came back online."])
    }

    @Test func nothingIsAskedDuringAScan() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: true)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func anUnavailableModelIsNotAskedAndShowsNothing() async {
        let insight = MockInsightService(isAvailable: false)
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    @Test func aFailedAnswerShowsNothing() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: home)

        await refreshAnswering(viewModel, insight, with: .failed)

        #expect(viewModel.brief == nil)
    }

    @Test func noChangesAsksNothing() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        events.log(NetworkEvent(type: .scanComplete, timestamp: now.addingTimeInterval(-60), title: "Scan Complete — 2 devices found",
                                networkProfileID: home))

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false)

        #expect(insight.requests.isEmpty)
        #expect(viewModel.brief == nil)
    }

    // MARK: - Scope

    @Test func anotherNetworksEventsAreLeftOut() async {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("cabin-tv", profileID: UUID())

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false)

        #expect(insight.requests.isEmpty)
    }

    @Test func eventsWithNoNetworkAreIncluded() async throws {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("uitest-printer", profileID: nil)

        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        let request = try #require(insight.requests.first)
        #expect(request.facts.contains("Joined: uitest-printer"))
    }

    @Test func theWindowIsTheLast24HoursInclusive() async throws {
        let insight = MockInsightService()
        let viewModel = makeViewModel(insight)
        logJoin("just-inside", profileID: home, secondsAgo: 86_400)
        logJoin("just-outside", profileID: home, ip: "192.168.77.21", secondsAgo: 86_401)

        await refreshAnswering(viewModel, insight, with: .finished(Self.answer))

        let request = try #require(insight.requests.first)
        #expect(request.facts.contains("Joined: just-inside"))
        #expect(!request.facts.contains("Joined: just-outside"))
    }

    // MARK: - Saved devices

    /// The shown network's rows and unassigned ones, read from the store rather than the scan
    /// coordinator, which holds whichever network it scanned last.
    @Test func savedDevicesAreTheShownNetworksAndUnassignedRowsUncapped() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        for index in 0..<(LocalDeviceQueries.defaultLimit + 1) {
            context.insert(LocalDevice(ipAddress: "10.1.\(index / 250).\(index % 250)", macAddress: "", networkProfileID: home))
        }
        context.insert(LocalDevice(ipAddress: "10.9.0.1", macAddress: "", networkProfileID: nil))
        context.insert(LocalDevice(ipAddress: "10.9.0.2", macAddress: "", networkProfileID: UUID()))
        try context.save()

        let rows = ChangeBriefMacViewModel.savedDevices(for: home, in: context)

        #expect(rows.count == LocalDeviceQueries.defaultLimit + 2)
        #expect(!rows.contains { $0.ipAddress == "10.9.0.2" })
    }

    // MARK: - UI-test seam

    @Test func theUITestAnswerPassesTheSummarizersChecks() async {
        let viewModel = makeViewModel(ChangeBriefMacViewModel.uiTestInsightService(arguments: ["--uitest-insight=answer"]))
        logJoin("uitest-printer", profileID: home)
        events.log(NetworkEvent(type: .connectivityChange, timestamp: now.addingTimeInterval(-60), title: "UITest Event Today",
                                networkProfileID: home))

        await viewModel.refresh(devices: [], networkProfileID: home, presence: noScans, isScanning: false)

        #expect(viewModel.brief?.text == ChangeBriefMacViewModel.uiTestAnswer)
        #expect(viewModel.brief?.keyPoints == ["1 device joined the network."])
    }

    @Test func theUITestInsightArgumentPicksTheService() {
        #expect(ChangeBriefMacViewModel.uiTestInsightService(arguments: ["--uitest-insight=answer"]).isAvailable)
        #expect(!ChangeBriefMacViewModel.uiTestInsightService(arguments: ["--uitest-insight=unavailable"]).isAvailable)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
