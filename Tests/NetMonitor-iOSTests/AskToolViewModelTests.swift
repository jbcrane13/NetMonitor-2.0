import Testing
import Foundation
import SwiftData
import NetMonitorCore
@testable import NetMonitor_iOS

/// Tools ▸ Ask's wiring on iOS (#452), with a scripted model.
@Suite("AskToolViewModel", .serialized)
@MainActor
struct AskToolViewModelTests {
    let home = UUID()

    func env(scanning: Bool = false, events: NetworkEventService = NetworkEventService()) -> AppEnvironment {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = scanning
        return AppEnvironment(
            networkMonitor: MockNetworkMonitorService(), deviceDiscovery: discovery,
            macConnection: MockMacConnectionService(), publicIP: MockPublicIPService(), wifiInfo: MockWiFiInfoService(),
            targetManager: .shared, activityLog: .shared, eventService: events, scanScheduler: ScanSchedulerService.shared
        )
    }

    static let printerQuestion = "Is the printer up?"
    static let model = ScriptedAskModel(scripts: [
        printerQuestion: AskScript(calls: [.findDevices("printer")], answer: "Office Printer is offline.")
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
        viewModel.update(devices: [device], networkProfileID: home)
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(answer) = viewModel.state.phase, let citation = answer.devices.first else {
            Issue.record("no device cited: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == "Office Printer is offline.")

        device.customName = "Upstairs Printer"
        viewModel.update(devices: [device], networkProfileID: home)
        let opened = viewModel.device(for: citation)
        #expect(opened?.id == device.id)
        #expect(opened?.displayName == "Upstairs Printer")
    }

    @Test func otherNetworksDevicesAreNotLookedUp() async {
        let viewModel = AskToolViewModel(env: env(), model: Self.model)
        viewModel.update(devices: [printer(network: UUID())], networkProfileID: home)
        await viewModel.state.ask(Self.printerQuestion)
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.devices.isEmpty)
        #expect(answer.text == nil)
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
        let viewModel = AskToolViewModel(env: env(), model: ScriptedAskModel(scripts: [:], isAvailable: false))
        #expect(!viewModel.state.isVisible)
    }

    // MARK: - Intent

    @Test func theIntentAnswersWithTheSamePipeline() async {
        let device = AskDevice(printer(network: nil))
        let text = await AskIntentRunner.answer(Self.printerQuestion, model: Self.model, devices: [device], events: [],
                                                networkProfileID: nil, isScanning: false)
        #expect(text == "Office Printer is offline.")
    }

    @Test func theIntentNamesTheCandidatesInsteadOfAPicker() async {
        let other = LocalDevice(ipAddress: "192.168.77.31", macAddress: "AA:00:00:00:00:31", deviceType: .printer, customName: "Den Printer")
        let text = await AskIntentRunner.answer(Self.printerQuestion, model: Self.model,
                                                devices: [AskDevice(printer(network: nil)), AskDevice(other)],
                                                events: [], networkProfileID: nil, isScanning: false)
        #expect(text == "Which one do you mean: Office Printer and Den Printer? Ask again with its name.")
    }

    @Test func theIntentSaysWhenItCantAsk() async {
        let unavailable = await AskIntentRunner.answer(Self.printerQuestion, model: ScriptedAskModel(scripts: [:], isAvailable: false),
                                                       devices: [], events: [], networkProfileID: nil, isScanning: false)
        #expect(unavailable == AskIntentRunner.unavailableMessage)
        let scanning = await AskIntentRunner.answer(Self.printerQuestion, model: Self.model, devices: [], events: [],
                                                    networkProfileID: nil, isScanning: true)
        #expect(scanning == AskState.scanMessage)
    }
}
