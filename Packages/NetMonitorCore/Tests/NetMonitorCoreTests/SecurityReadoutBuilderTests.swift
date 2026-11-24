import Testing
import Foundation
@testable import NetMonitorCore

@Suite("SecurityReadoutBuilder")
struct SecurityReadoutBuilderTests {
    func device(_ name: String, _ type: DeviceType, ports: [Int]) -> LocalDevice {
        LocalDevice(ipAddress: "192.168.1.9", macAddress: "AA:BB:CC:00:00:09", deviceType: type, customName: name, openPorts: ports)
    }

    @Test func noFindingsAsksNothing() {
        #expect(SecurityReadoutBuilder.request(findings: []) == nil)
    }

    @Test func factsAndKeyPointsAreCountsBySeverityAndService() throws {
        let findings = SecurityRuleTable.findings(for: [
            device("Garage Camera", .camera, ports: [23, 80]),
            device("printer.lan", .printer, ports: [80]),
            device("NAS", .storage, ports: [445])
        ])
        let request = try #require(SecurityReadoutBuilder.request(findings: findings))
        #expect(request.kind == .summary)
        #expect(request.subject == "Security readout of the devices on this network")
        #expect(request.observations == [
            "1 high severity finding: Telnet.",
            "1 medium severity finding: HTTP admin page.",
            "2 low severity findings: SMB file sharing, HTTP admin page."
        ])
        #expect(request.facts == [
            "Number of findings: 4",
            "High severity findings: 1",
            "Medium severity findings: 1",
            "Low severity findings: 2",
            "Devices with findings: 3",
            "Telnet findings: 1",
            "HTTP admin page findings: 2",
            "SMB file sharing findings: 1"
        ])
    }

    /// The overview can't pair a device with a port: neither is in the prompt (#550 review).
    @Test func thePromptNamesNoDeviceAndNoPort() throws {
        let findings = SecurityRuleTable.findings(for: [
            device("Garage Camera", .camera, ports: [23, 80, 22]),
            device("Router", .router, ports: [5000, 8080]),
            device("Build server", .unknown, ports: [6379, 3306, 27017, 5432, 3389, 5900, 21, 139, 445])
        ])
        let request = try #require(SecurityReadoutBuilder.request(findings: findings))
        for name in ["Garage Camera", "Router", "Build server"] {
            #expect(!request.prompt.contains(name), "\(name) is in the prompt")
        }
        let given = Set(InsightGrounding.numbers(in: request.prompt))
        for port in SecurityRuleTable.ports {
            #expect(!given.contains(Double(port)), "port \(port) is in the prompt")
        }
    }
}
