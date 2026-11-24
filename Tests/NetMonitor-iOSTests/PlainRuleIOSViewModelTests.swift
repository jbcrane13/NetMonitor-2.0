import Foundation
import NetMonitorCore
import SwiftData
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
                    deviceType: .storage, openPorts: [445], networkProfileID: home)
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
        #expect(model.takePortScan() == PortScanRequest(host: "192.168.1.20", preset: .web))
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

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MonitoringTarget.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func theTargetDraftsNameAndAddressAreEditedBeforeConfirm() async throws {
        let container = try makeContainer()
        let model = viewModel("Tell me if the NAS is down for more than five minutes")
        await model.submit(devices: [homeNAS()], targets: [], networkID: home, isScanning: false)
        #expect(try container.mainContext.fetch(FetchDescriptor<MonitoringTarget>()).isEmpty, "Nothing saved before Confirm")

        model.targetDraft?.name = "  Basement NAS "
        model.targetDraft?.host = "nas.local"
        model.confirm(context: container.mainContext)

        let saved = try container.mainContext.fetch(FetchDescriptor<MonitoringTarget>())
        #expect(saved.map(\.name) == ["Basement NAS"])
        #expect(saved.map(\.host) == ["nas.local"])
        #expect(model.targetDraft == nil)
    }

    @Test func aTargetDraftWithoutAnAddressCantBeConfirmed() async throws {
        let container = try makeContainer()
        let model = viewModel("Tell me if the NAS is down for more than five minutes")
        await model.submit(devices: [homeNAS()], targets: [], networkID: home, isScanning: false)
        model.targetDraft?.host = "  "
        #expect(!model.canConfirmTarget)
        model.confirm(context: container.mainContext)
        #expect(try container.mainContext.fetch(FetchDescriptor<MonitoringTarget>()).isEmpty)
    }

    @Test func deletingATargetRemovesItFromTheStore() throws {
        let container = try makeContainer()
        let keep = MonitoringTarget(name: "Router", host: "192.168.1.1")
        let drop = MonitoringTarget(name: "NAS", host: "192.168.1.40")
        container.mainContext.insert(keep)
        container.mainContext.insert(drop)
        try container.mainContext.save()

        viewModel("").delete([drop], context: container.mainContext)

        #expect(try container.mainContext.fetch(FetchDescriptor<MonitoringTarget>()).map(\.host) == ["192.168.1.1"])
    }
}
