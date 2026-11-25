import Testing
import Foundation
import SwiftData
import NetMonitorCore
@testable import NetMonitor_macOS

/// Tools ▸ Ask's wiring on the Mac (#452), with a scripted model.
@Suite("AskMacViewModel")
@MainActor
struct AskMacViewModelTests {
    let home = UUID()
    static let model = ScriptedAskModel(scripts: [
        "Is the printer up?": AskScript(calls: [.findDevices("printer")], answer: "Office Printer is a printer.")
    ])

    func printer(network: UUID?) -> LocalDevice {
        LocalDevice(ipAddress: "192.168.77.30", macAddress: "AA:00:00:00:00:30", deviceType: .printer, customName: "Office Printer",
                    status: .offline, networkProfileID: network)
    }

    @Test func aCitationStillOpensTheSameRecordAfterARename() async throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let device = printer(network: home)
        container.mainContext.insert(device)
        let viewModel = AskMacViewModel(model: Self.model, events: NetworkEventService())
        viewModel.update(devices: [device], networkProfileID: home, lastScan: nil, isScanning: false)
        await viewModel.state.ask("Is the printer up?")
        guard case let .answered(answer) = viewModel.state.phase, let citation = answer.devices.first else {
            Issue.record("no device cited: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == "Office Printer is a printer.")
        #expect(answer.devices.first?.presence == .notChecked)

        device.customName = "Upstairs Printer"
        viewModel.update(devices: [device], networkProfileID: home, lastScan: nil, isScanning: false)
        #expect(viewModel.device(for: citation)?.id == device.id)
        #expect(viewModel.device(for: citation)?.displayName == "Upstairs Printer")
    }

    /// The Mac's last scan of this network finished 40 minutes ago and saw the NAS: Ask says the
    /// status is not recent and drops an answer that calls it online now.
    @Test func aDeviceTheLastScanSawFortyMinutesAgoIsNeverOnlineNow() async {
        let scanEnd = Date().addingTimeInterval(-40 * 60)
        // Stamped while merging, a moment before the profile's lastScanned.
        let nas = LocalDevice(ipAddress: "192.168.77.40", macAddress: "AA:00:00:00:00:40", deviceType: .storage,
                              customName: "Garage NAS", status: .online, networkProfileID: home)
        nas.lastSeen = scanEnd.addingTimeInterval(-20)
        let model = ScriptedAskModel(scripts: [
            "What's online?": AskScript(calls: [.findDevices("all")], answer: "Garage NAS is online."),
            "Is the NAS up?": AskScript(calls: [.deviceStatus("NAS")], answer: "Garage NAS was last seen 40 minutes ago.")
        ])
        let viewModel = AskMacViewModel(model: model, events: NetworkEventService())
        viewModel.update(devices: [nas], networkProfileID: home, lastScan: scanEnd, isScanning: false)

        await viewModel.state.ask("What's online?")
        guard case let .answered(online) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(online.text == nil)
        #expect(online.shownText == AskNetwork.staleFallback)
        #expect(online.freshness?.hasPrefix("Not checked recently: the last scan was 40 minutes ago (") == true)

        await viewModel.state.ask("Is the NAS up?")
        guard case let .answered(status) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        // Within the tolerance, the NAS answered that scan: the app shows it beside the citation.
        #expect(status.text == "Garage NAS was last seen 40 minutes ago.")
        #expect(status.devices.first?.presence == .answeredOldScan)
    }

    @Test func nothingIsAskedDuringAScan() async {
        let viewModel = AskMacViewModel(model: Self.model, events: NetworkEventService())
        viewModel.update(devices: [printer(network: home)], networkProfileID: home, lastScan: nil, isScanning: true)
        await viewModel.state.ask("Is the printer up?")
        #expect(viewModel.state.phase == .stopped(AskState.scanMessage))
    }

    @Test func otherNetworksDevicesAreNotLookedUp() async {
        let viewModel = AskMacViewModel(model: Self.model, events: NetworkEventService())
        viewModel.update(devices: [printer(network: UUID())], networkProfileID: home, lastScan: nil, isScanning: false)
        await viewModel.state.ask("Is the printer up?")
        guard case let .answered(answer) = viewModel.state.phase else {
            Issue.record("not answered: \(viewModel.state.phase)")
            return
        }
        #expect(answer.devices.isEmpty)
        #expect(answer.text == nil)
    }

    @Test func askIsListedUnderMonitoringOnlyWithTheModel() {
        #expect(ToolCategory.monitoring.tools(showsAsk: true).contains(.ask))
        #expect(!ToolCategory.monitoring.tools(showsAsk: false).contains(.ask))
        #expect(ToolCategory.allCases.filter { $0.tools(showsAsk: true).contains(.ask) } == [.monitoring])
        #expect(!AskMacViewModel(model: UnavailableAskModel()).state.isVisible)
    }

    @Test func theUITestModeComesFromItsArgument() {
        #expect(AskMacViewModel.uiTestMode(arguments: ["--uitesting", "--uitest-ask=answer"]) == .answer)
        #expect(AskMacViewModel.uiTestMode(arguments: ["--uitest-ask=answer"]) == nil)
    }
}
