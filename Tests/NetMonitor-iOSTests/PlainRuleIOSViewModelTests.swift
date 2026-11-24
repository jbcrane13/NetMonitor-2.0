import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

@Suite("Plain-English rules on iOS (#450)")
@MainActor
struct PlainRuleIOSViewModelTests {
    private let home = UUID()
    private let office = UUID()

    private func officePrinter() -> LocalDevice {
        LocalDevice(ipAddress: "192.168.1.20", macAddress: "02:00:00:01:00:20", hostname: "office-printer",
                    deviceType: .printer, networkProfileID: office)
    }

    private func homeNAS() -> LocalDevice {
        LocalDevice(ipAddress: "192.168.1.40", macAddress: "02:00:00:01:00:40", hostname: "home-nas",
                    deviceType: .storage, networkProfileID: home)
    }

    private func viewModel(_ text: String) -> PlainRuleIOSViewModel {
        let model = PlainRuleIOSViewModel(parser: FixedRuleIntentParser.uiTest)
        model.text = text
        return model
    }

    /// The printer saved at the office has an address that belongs to some other device at home.
    @Test func aDeviceSavedOnAnotherNetworkIsNotOfferedForAPortScan() async {
        let model = viewModel("scan web ports on the printer")

        await model.submit(devices: [officePrinter(), homeNAS()], targets: [], networkID: home, isScanning: false)

        #expect(model.composer.outcome == .message("No device on this network matches “printer”."))
        #expect(model.takePortScan() == nil)
    }

    @Test func aDeviceOnTheCurrentNetworkIsResolved() async {
        let printer = officePrinter()
        let model = viewModel("scan web ports on the printer")

        await model.submit(devices: [printer, homeNAS()], targets: [], networkID: office, isScanning: false)

        #expect(model.composer.outcome == .portScan(device: RuleDevice(printer), preset: .web))
        #expect(model.takePortScan() == PlainRuleIOSViewModel.PortScanRequest(host: "192.168.1.20", preset: .web))
    }

    @Test func withoutAKnownNetworkEverySavedDeviceCanBeNamed() async {
        let nas = homeNAS()
        let model = viewModel("Tell me if the NAS is down for more than five minutes")

        await model.submit(devices: [officePrinter(), nas], targets: [], networkID: nil, isScanning: false)

        guard case let .target(draft) = model.composer.outcome else {
            Issue.record("Expected a target draft, got \(String(describing: model.composer.outcome))")
            return
        }
        #expect(draft.host == "192.168.1.40")
        #expect(draft.deviceID == nas.id)
    }
}
