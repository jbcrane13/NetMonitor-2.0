import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

/// Tools ▸ Troubleshoot's wiring on the Mac (#451).
@Suite("TroubleshootMacViewModel")
@MainActor
struct TroubleshootMacViewModelTests {
    let home = UUID()

    @Test func onlyTheCurrentNetworksDevicesAndUnassignedOnesAreOffered() {
        let viewModel = TroubleshootMacViewModel(arguments: [])
        let nas = LocalDevice(ipAddress: "192.168.77.40", macAddress: "AA:00:00:00:00:40", deviceType: .storage, customName: "NAS",
                              openPorts: [445], networkProfileID: home)
        let elsewhere = LocalDevice(ipAddress: "10.9.0.4", macAddress: "AA:00:00:00:00:04", deviceType: .printer,
                                    customName: "Office Printer", networkProfileID: UUID())
        viewModel.update(devices: [nas, elsewhere], networkProfileID: home, isScanning: false)
        #expect(viewModel.savedDevices.map(\.displayName) == ["NAS"])
        #expect(viewModel.savedDevices.first?.openPorts == [445])
    }

    @Test func nothingRunsDuringAScan() async {
        let viewModel = TroubleshootMacViewModel(arguments: [])
        viewModel.update(devices: [], networkProfileID: home, isScanning: true)
        await viewModel.state.choose(.slowOrUnstableInternet)
        #expect(viewModel.state.phase == .stopped(TroubleshootState.scanMessage))
        #expect(viewModel.state.steps.isEmpty)
    }

    @Test func theFixtureNeedsUITestingAndAKnownMode() {
        #expect(TroubleshootMacViewModel.uiTestMode(arguments: ["--uitesting", "--uitest-troubleshoot=hold"]) == .hold)
        #expect(TroubleshootMacViewModel.uiTestMode(arguments: ["--uitest-troubleshoot=hold"]) == nil)
        #expect(TroubleshootMacViewModel.uiTestMode(arguments: ["--uitesting", "--uitest-troubleshoot=nope"]) == nil)
        #expect(!TroubleshootMacViewModel(arguments: ["--uitesting", "--uitest-troubleshoot=unavailable"]).state.canDescribe)
    }

    @Test func listedUnderDiagnostics() {
        #expect(ToolCategory.allCases.filter { $0.tools.contains(.troubleshoot) } == [.diagnostics])
        #expect(NetworkTool.troubleshoot.cardIdentifier == "tools_card_troubleshoot")
    }
}
