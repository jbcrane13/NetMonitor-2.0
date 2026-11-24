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

    @Test func factsAndKeyPointsFollowTheRankedFindings() throws {
        let findings = SecurityRuleTable.findings(for: [
            device("Garage Camera", .camera, ports: [23, 80]),
            device("printer.lan", .printer, ports: [80]),
            device("NAS", .storage, ports: [445])
        ])
        let request = try #require(SecurityReadoutBuilder.request(findings: findings))
        #expect(request.kind == .summary)
        #expect(request.subject == "Security readout of the devices on this network")
        #expect(request.observations == [
            "Telnet port 23 is open on Garage Camera, high severity.",
            "HTTP admin page port 80 is open on Garage Camera, medium severity.",
            "SMB file sharing port 445 is open on NAS, low severity."
        ])
        #expect(request.facts == [
            "Number of findings: 4",
            "High severity findings: 1",
            "Medium severity findings: 1",
            "Low severity findings: 2",
            "Devices with findings: 3",
            "Finding 1 device: Garage Camera",
            "Finding 1: Telnet port 23 is open, high severity",
            "Finding 2 device: Garage Camera",
            "Finding 2: HTTP admin page port 80 is open, medium severity",
            "Finding 3 device: NAS",
            "Finding 3: SMB file sharing port 445 is open, low severity",
            "Finding 4 device: printer.lan",
            "Finding 4: HTTP admin page port 80 is open, low severity"
        ])
    }

    @Test func longListsAreCappedInThePromptOnly() throws {
        let devices = (1...12).map { device("Camera \($0)", .camera, ports: [23]) }
        let findings = SecurityRuleTable.findings(for: devices)
        let request = try #require(SecurityReadoutBuilder.request(findings: findings))
        #expect(findings.count == 12)
        #expect(request.facts.first == "Number of findings: 12")
        #expect(request.facts.count { $0.hasPrefix("Finding ") && $0.contains(" device: ") } == SecurityReadoutBuilder.promptLimit)
        #expect(request.facts.last == "Findings not listed here: 4")
        #expect(request.observations.count == SecurityReadoutBuilder.keyPointLimit)
    }
}
