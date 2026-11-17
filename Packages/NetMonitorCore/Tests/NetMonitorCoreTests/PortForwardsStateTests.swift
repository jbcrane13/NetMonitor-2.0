import Testing
import Foundation
import NetworkScanKit
@testable import NetMonitorCore

@Suite("PortForwardsState")
@MainActor
struct PortForwardsStateTests {

    private static func mapping(
        _ external: UInt16,
        _ proto: UPnPPortMapping.TransportProtocol = .udp,
        client: String = "192.168.1.17",
        lease: Int = 0
    ) -> UPnPPortMapping {
        UPnPPortMapping(
            externalPort: external, transportProtocol: proto, internalClient: client, internalPort: 41641,
            description: "NAT-PMP \(external) udp", leaseSeconds: lease, isEnabled: true, remoteHost: nil
        )
    }

    @Test("rows match known device names by IP, else show the address, sorted by port")
    func rowsMatchNamesAndSort() {
        let rows = PortForwardsState.rows(
            from: [Self.mapping(41643), Self.mapping(443, .tcp, client: "192.168.1.30"), Self.mapping(443, .udp, client: "192.168.1.30")],
            deviceNames: ["192.168.1.17": "Blake's iPhone", "192.168.1.30": ""]
        )
        #expect(rows.map(\.id) == ["TCP-443", "UDP-443", "UDP-41643"])
        #expect(rows.last?.clientLabel == "Blake's iPhone")
        #expect(rows.first?.clientLabel == "192.168.1.30")
        #expect(rows.first?.deviceName == nil)
    }

    @Test("lease text", arguments: [(0, "Permanent"), (45, "45 s"), (600, "10 min"), (3600, "1 h"), (4875, "1 h 21 min")])
    func leaseText(seconds: Int, text: String) {
        #expect(PortForwardsState.leaseText(seconds: seconds) == text)
    }

    @Test("each report maps to its own state; no answer is never shown as no forwards")
    func reportToPhase() {
        #expect(PortForwardsState.phase(for: nil, deviceNames: [:]) == .noLocalNetwork)
        #expect(PortForwardsState.phase(for: .noGateway, deviceNames: [:]) == .noGateway)
        #expect(PortForwardsState.phase(for: .noWANService, deviceNames: [:]) == .noWANService)
        #expect(PortForwardsState.phase(for: .mappings([], isComplete: true), deviceNames: [:]) == .loaded([], isComplete: true))
        if case let .loaded(rows, isComplete) = PortForwardsState.phase(for: .mappings([Self.mapping(1)], isComplete: false), deviceNames: [:]) {
            #expect(rows.count == 1)
            #expect(!isComplete)
        } else {
            Issue.record("expected loaded")
        }
    }

    @Test("load reads through the service for the given interface and publishes the rows")
    func loadPublishesRows() async {
        let service = MockPortMappingService(report: .mappings([Self.mapping(41643)], isComplete: true))
        let state = PortForwardsState(service: service)

        state.load(interface: "en1", deviceNames: ["192.168.1.17": "Phone"])
        #expect(state.isLoading)
        await state.waitForLoad()

        #expect(await service.interfaces == ["en1"])
        guard case let .loaded(rows, isComplete) = state.phase else {
            Issue.record("expected loaded")
            return
        }
        #expect(rows.first?.clientLabel == "Phone")
        #expect(isComplete)
    }

    @Test("cancel returns a loading state to idle")
    func cancelResetsLoading() {
        let state = PortForwardsState(service: MockPortMappingService(report: .noGateway))
        state.load(interface: "en0", deviceNames: [:])
        state.cancel()
        #expect(state.phase == .idle)
    }
}

private actor MockPortMappingService: UPnPPortMappingServiceProtocol {
    private let report: UPnPPortMappingReport?
    private(set) var interfaces: [String] = []

    init(report: UPnPPortMappingReport?) {
        self.report = report
    }

    func readPortMappings(interface: String) async -> UPnPPortMappingReport? {
        interfaces.append(interface)
        return report
    }
}
