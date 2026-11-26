import Testing
import Foundation
import SwiftData
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_iOS

/// Tools ▸ Ask's wiring on iOS (#452), with a scripted model.
@Suite("AskToolViewModel", .serialized)
@MainActor
struct AskToolViewModelTests {
    let home = UUID()

    /// The network the phone is on, as `AppEnvironment.currentNetworkProfileID` reads it.
    @MainActor
    final class Network {
        var id: UUID?
        init(_ id: UUID?) { self.id = id }
    }

    func env(scanning: Bool = false, events: NetworkEventService = NetworkEventService(), network: Network? = nil) -> AppEnvironment {
        let network = network ?? Network(home)
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = scanning
        return AppEnvironment(
            networkMonitor: MockNetworkMonitorService(), deviceDiscovery: discovery,
            macConnection: MockMacConnectionService(), publicIP: MockPublicIPService(), wifiInfo: MockWiFiInfoService(),
            targetManager: .shared, activityLog: .shared, eventService: events, scanScheduler: ScanSchedulerService.shared,
            currentNetworkProfileID: { network.id }
        )
    }

    static let printerQuestion = "Is the printer up?"
    static let model = ScriptedAskModel(scripts: [
        printerQuestion: AskScript(calls: [.findDevices("printer")], answer: "Office Printer is a printer.")
    ])

    func printer(network: UUID?) -> LocalDevice {
        LocalDevice(ipAddress: "192.168.77.30", macAddress: "AA:00:00:00:00:30", deviceType: .printer, customName: "Office Printer",
                    status: .offline, networkProfileID: network)
    }

    @Test func aCitationStillOpensTheSameRecordAfterARename() async throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let device = printer(network: home)
        container.mainContext.insert(device)
        let viewModel = AskToolViewModel(env: env(), model: Self.model)
        viewModel.update(devices: [device])
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(answer) = viewModel.state.phase, let citation = answer.devices.first else {
            Issue.record("no device cited: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == "Office Printer is a printer.")

        device.customName = "Upstairs Printer"
        viewModel.update(devices: [device])
        let opened = viewModel.device(for: citation)
        #expect(opened?.id == device.id)
        #expect(opened?.displayName == "Upstairs Printer")
    }

    /// The brief's case, through a real reconcile: the phone's last scan of this network, 40 minutes
    /// ago, saw the NAS. Ask says how old that is and never lets the model call it online now.
    @Test func aDeviceTheLastScanSawFortyMinutesAgoIsNeverOnlineNow() async throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "AskToolViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistory(defaults: defaults)
        let scanTime = Date().addingTimeInterval(-40 * 60)
        let nas = DiscoveredDevice(
            ipAddress: "192.168.77.40", hostname: "garage-nas", vendor: nil, macAddress: "AA:00:00:00:00:40", latency: 3,
            discoveredAt: scanTime, source: .local, networkProfileID: home
        )
        try ScanReconciler(context: container.mainContext, history: history)
            .reconcile([nas], networkProfileID: home, scanDate: scanTime, now: scanTime)
        let rows = try container.mainContext.fetch(FetchDescriptor<LocalDevice>())
        let row = try #require(rows.first)
        #expect(row.status == .online)

        let model = ScriptedAskModel(scripts: ["What's online?": AskScript(calls: [.findDevices("all")], answer: "\(row.displayName) is online.")])
        let viewModel = AskToolViewModel(env: env(), model: model, history: history)
        viewModel.update(devices: rows)
        await viewModel.state.ask("What's online?")
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.staleFallbackOne)
        #expect(answer.devices.map(\.id) == [row.id])
        #expect(answer.freshness?.hasPrefix("Not checked recently: the last scan was 40 minutes ago (") == true)
    }

    @Test func otherNetworksDevicesAreNotLookedUp() async {
        let viewModel = AskToolViewModel(env: env(), model: Self.model)
        viewModel.update(devices: [printer(network: UUID())])
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.devices.isEmpty)
        #expect(answer.text == nil)
    }

    @Test func aNetworkChangeAfterTheViewOpenedIsSeenByTheNextQuestion() async {
        let network = Network(home)
        let viewModel = AskToolViewModel(env: env(network: network), model: Self.model)
        viewModel.update(devices: [printer(network: home)])
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(atHome) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(atHome.devices.map(\.name) == ["Office Printer"])

        // The phone joins another network; the saved rows and the view are unchanged.
        network.id = UUID()
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(away) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(away.devices.isEmpty)
        #expect(away.text == nil)
    }

    @Test func eventsComeFromTheAppsEventLog() async {
        let events = NetworkEventService()
        events.log(NetworkEvent(type: .deviceJoined, timestamp: Date().addingTimeInterval(-3600), title: "Device Joined: Garage Plug"))
        let model = ScriptedAskModel(scripts: [
            "What joined this week?": AskScript(calls: [.events(range: "last7Days", type: "joined")], answer: "Garage Plug joined.")
        ])
        let viewModel = AskToolViewModel(env: env(events: events), model: model)
        await viewModel.state.ask("What joined this week?")
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == "Garage Plug joined.")
        #expect(answer.events.map(\.title) == ["Device Joined: Garage Plug"])
    }

    @Test func nothingIsAskedWhileTheAppsDiscoveryScans() async {
        let viewModel = AskToolViewModel(env: env(scanning: true), model: Self.model)
        await viewModel.state.ask(Self.printerQuestion)
        #expect(viewModel.state.phase == .stopped(AskState.scanMessage))
    }

    @Test func theCardIsHiddenWithoutTheModel() {
        let viewModel = AskToolViewModel(env: env(), model: UnavailableAskModel())
        #expect(!viewModel.state.isVisible)
    }

    // MARK: - Intent

    private func intent(
        model: any AskModelProtocol = Self.model, devices: [AskDevice], lastScan: Date?, isScanning: Bool = false
    ) async -> String {
        let snapshot = AskSnapshot(devices: devices, events: [], lastScan: lastScan, now: Date())
        return await AskIntentRunner.answer(Self.printerQuestion, model: model, snapshot: snapshot, isScanning: isScanning)
    }

    @Test func theIntentAnswersWithTheSamePipelineAndSaysHowFresh() async {
        let device = AskDevice(DeviceGroups.project([printer(network: nil)])[0])
        let text = await intent(devices: [device], lastScan: Date(), isScanning: false)
        #expect(text.hasPrefix("Office Printer is a printer. Office Printer: Offline. Device status as of the scan less than a minute ago ("))
        let unscanned = await intent(devices: [device], lastScan: nil, isScanning: false)
        #expect(unscanned == "Office Printer is a printer. Office Printer: Not checked recently. "
            + "This network hasn't been scanned yet, so no device's status has been checked.")
    }

    @Test func theIntentNamesTheCandidatesInsteadOfAPicker() async {
        let other = LocalDevice(ipAddress: "192.168.77.31", macAddress: "AA:00:00:00:00:31", deviceType: .printer, customName: "Den Printer")
        let text = await intent(devices: [AskDevice(DeviceGroups.project([printer(network: nil)])[0]), AskDevice(DeviceGroups.project([other])[0])], lastScan: nil, isScanning: false)
        #expect(text == "Which one do you mean: Office Printer and Den Printer? Ask again with its name.")
    }

    @Test func theIntentSaysWhenItCantAsk() async {
        let unavailable = await intent(model: UnavailableAskModel(), devices: [], lastScan: nil, isScanning: false)
        #expect(unavailable == AskIntentRunner.unavailableMessage)
        let scanning = await intent(devices: [], lastScan: nil, isScanning: true)
        #expect(scanning == AskState.scanMessage)
    }
}
