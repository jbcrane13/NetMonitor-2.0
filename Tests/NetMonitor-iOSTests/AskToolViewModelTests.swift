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
        let devices = [AskDevice(DeviceGroups.project([printer(network: nil)])[0]), AskDevice(DeviceGroups.project([other])[0])]
        let text = await intent(devices: devices, lastScan: nil, isScanning: false)
        #expect(text == "Which one do you mean: Office Printer and Den Printer? Ask again with its name.")
    }

    @Test func theIntentSaysWhenItCantAsk() async {
        let unavailable = await intent(model: UnavailableAskModel(), devices: [], lastScan: nil, isScanning: false)
        #expect(unavailable == AskIntentRunner.unavailableMessage)
        let scanning = await intent(devices: [], lastScan: nil, isScanning: true)
        #expect(scanning == AskState.scanMessage)
    }

    // MARK: - Live tools (#579)

    /// "Is the printer answering right now?" on a network with no scan: the app refuses to ping
    /// and says to scan first (#579 review). A live tool was called, so no model text shows, and
    /// the saved status stays the scan's.
    @Test func aPingQuestionBeforeAnyScanIsRefusedByTheApp() async {
        let printer = LocalDevice(
            ipAddress: AskUITestFixture.printer.ip, macAddress: AskUITestFixture.printer.mac, deviceType: .printer,
            customName: AskUITestFixture.printer.name, status: .offline, networkProfileID: home
        )
        let home = home
        let viewModel = AskToolViewModel(env: env(), model: AskUITestFixture.model(.answer), live: AskUITestFixture.live { home })
        viewModel.update(devices: [printer])
        await viewModel.state.ask(AskUITestFixture.pingQuestion)
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements == [AskMeasurement(deviceID: printer.id, text: AskUITestFixture.pingRefusal, measuredAt: nil)])
        #expect(answer.devices.map(\.presence) == [.notCheckedRecently])
        #expect(printer.status == .offline)
    }

    // MARK: - Intent and live tools

    private func device(_ name: String, ip: String) -> AskDevice {
        AskDevice(id: UUID(), displayName: name, deviceType: .storage, maker: nil, ipAddress: ip, status: .online,
                  lastSeen: Date(), lastLatency: nil, latencyHistory: [])
    }

    private func intentAnswer(_ question: String, script: AskScript, devices: [AskDevice], lastScan: Date?) async -> String {
        let snapshot = AskSnapshot(devices: devices, events: [], networkProfileID: home, lastScan: lastScan, now: Date())
        let home = home
        return await AskIntentRunner.answer(
            question, model: ScriptedAskModel(scripts: [question: script]), snapshot: snapshot, isScanning: false,
            live: AskUITestFixture.live { home }
        )
    }

    @Test func theIntentSaysWhatTheAppMeasured() async {
        let text = await intentAnswer(AskUITestFixture.statusQuestion, script: AskScript(calls: [.networkStatus], answer: "It is fine."),
                                      devices: [], lastScan: nil)
        #expect(text == "Here is the app's live check. " + AskUITestFixture.statusMeasurement + ", measured just now.")
    }

    /// Siri speaks the measurement, never a chip status that could contradict it.
    @Test func theIntentPingsAndSpeaksTheMeasurementNotTheChip() async {
        let nas = device("Garage NAS", ip: AskUITestFixture.printer.ip)
        let text = await intentAnswer("Is the NAS up?", script: AskScript(calls: [.pingDevice("Garage NAS")], answer: "Yes, it pinged fine."),
                                      devices: [nas], lastScan: Date())
        #expect(text.hasPrefix("Here is the app's live check. Garage NAS (192.0.2.57): 3 of 3 replies, 4 ms average, measured just now. "))
        #expect(!text.contains("Garage NAS: Online"))
        #expect(!text.contains("below"))
        // Every cited device was checked live, so the scan's freshness isn't said.
        #expect(!text.contains("Device status as of the scan"))
    }

    /// A silent ping of a device the scan saw Online: the measurement, then the scan's word.
    @Test func theIntentSaysWhenTheScanDisagreed() async {
        let quiet = device("Garage NAS", ip: "192.0.2.99")
        let text = await intentAnswer("Is the NAS up?", script: AskScript(calls: [.pingDevice("Garage NAS")], answer: "No."),
                                      devices: [quiet], lastScan: Date())
        #expect(text.contains("Garage NAS (192.0.2.99): no reply to 3 pings, measured just now. At the last scan "))
        #expect(text.contains(" it was online."))
    }

    /// Refusals aren't measurements: no "measured just now".
    @Test func theIntentNeverSaysARefusalWasMeasured() async {
        let nas = device("Garage NAS", ip: AskUITestFixture.printer.ip)
        let text = await intentAnswer("Is the NAS up?", script: AskScript(calls: [.pingDevice("Garage NAS")], answer: "No."),
                                      devices: [nas], lastScan: nil)
        #expect(text.contains("Garage NAS (192.0.2.57): not pinged. Run a scan first"))
        #expect(!text.contains("measured just now"))
        #expect(!text.contains(".."))
    }

    /// At most two live checks in one Siri turn.
    @Test func theIntentMakesAtMostTwoLiveChecks() async {
        let devices = (1 ... 3).map { device("Box \($0)", ip: "192.0.2.\(60 + $0)") }
        let calls = devices.map { AskToolCall.pingDevice($0.displayName) }
        let text = await intentAnswer("Are the boxes up?", script: AskScript(calls: calls, answer: "No."), devices: devices, lastScan: Date())
        #expect(text.contains("Box 1 (192.0.2.61)"))
        #expect(text.contains("Box 2 (192.0.2.62)"))
        #expect(!text.contains("Box 3 (192.0.2.63)"))
    }

    /// A model that ignores cancellation and takes 5 s.
    struct UncooperativeAskModel: AskModelProtocol {
        var isAvailable: Bool { true }

        func answer(_ question: String, instructions: String, toolbox: AskToolbox) async -> String? {
            let end = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < end {
                try? await Task.sleep(for: .milliseconds(50))
            }
            return "Late."
        }
    }

    /// The turn's deadline is hard (#627 verification): Siri doesn't wait for a model that ignores
    /// cancellation.
    @Test func theIntentTurnHasAHardDeadline() async {
        let snapshot = AskSnapshot(devices: [], events: [], networkProfileID: home, lastScan: nil, now: Date())
        let clock = ContinuousClock(), start = clock.now
        let text = await AskIntentRunner.answer(
            "Q", model: UncooperativeAskModel(), snapshot: snapshot, isScanning: false, live: nil, deadline: .milliseconds(200)
        )
        #expect(text == AskIntentRunner.timedOutMessage)
        #expect(clock.now - start < .seconds(2))
    }

    /// Cancelling the intent reaches the turn: it ends without waiting for the model.
    @Test func cancellingTheIntentEndsTheTurn() async {
        let snapshot = AskSnapshot(devices: [], events: [], networkProfileID: home, lastScan: nil, now: Date())
        let clock = ContinuousClock(), start = clock.now
        let task = Task {
            await AskIntentRunner.answer("Q", model: UncooperativeAskModel(), snapshot: snapshot, isScanning: false, live: nil)
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        #expect(await task.value == AskIntentRunner.timedOutMessage)
        #expect(clock.now - start < .seconds(2))
    }
}
