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
        "Is the printer up?": AskScript(calls: [.findDevices("printer")], answer: "Office Printer is offline.")
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
        viewModel.update(devices: [device], networkProfileID: home, isScanning: false)
        await viewModel.state.ask("Is the printer up?")
        guard case let .answered(answer) = viewModel.state.phase, let citation = answer.devices.first else {
            Issue.record("no device cited: \(viewModel.state.phase)")
            return
        }
        #expect(answer.text == "Office Printer is offline.")

        device.customName = "Upstairs Printer"
        viewModel.update(devices: [device], networkProfileID: home, isScanning: false)
        #expect(viewModel.device(for: citation)?.id == device.id)
        #expect(viewModel.device(for: citation)?.displayName == "Upstairs Printer")
    }

    @Test func nothingIsAskedDuringAScan() async {
        let viewModel = AskMacViewModel(model: Self.model, events: NetworkEventService())
        viewModel.update(devices: [printer(network: home)], networkProfileID: home, isScanning: true)
        await viewModel.state.ask("Is the printer up?")
        #expect(viewModel.state.phase == .stopped(AskState.scanMessage))
    }

    @Test func otherNetworksDevicesAreNotLookedUp() async {
        let viewModel = AskMacViewModel(model: Self.model, events: NetworkEventService())
        viewModel.update(devices: [printer(network: UUID())], networkProfileID: home, isScanning: false)
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
        #expect(!AskMacViewModel(model: ScriptedAskModel(scripts: [:], isAvailable: false)).state.isVisible)
    }

    @Test func theUITestModeComesFromItsArgument() {
        #expect(AskMacViewModel.uiTestMode(arguments: ["--uitesting", "--uitest-ask=answer"]) == .answer)
        #expect(AskMacViewModel.uiTestMode(arguments: ["--uitest-ask=answer"]) == nil)
    }
}
