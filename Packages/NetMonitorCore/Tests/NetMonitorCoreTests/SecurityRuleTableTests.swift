import Testing
import Foundation
@testable import NetMonitorCore

@Suite("SecurityRuleTable")
struct SecurityRuleTableTests {
    func device(_ name: String, _ type: DeviceType = .unknown, ports: [Int]?) -> LocalDevice {
        LocalDevice(ipAddress: "192.168.1.9", macAddress: "AA:BB:CC:00:00:09", deviceType: type, customName: name, openPorts: ports)
    }

    @Test func telnetOnACameraIsHigh() {
        let camera = device("Garage Camera", .camera, ports: [23])
        let findings = SecurityRuleTable.findings(for: [camera])
        #expect(findings.count == 1)
        let finding = findings.first
        #expect(finding?.ruleID == "telnet")
        #expect(finding?.port == 23)
        #expect(finding?.severity == .high)
        #expect(finding?.deviceID == camera.id)
        #expect(finding?.deviceName == "Garage Camera")
        #expect(finding?.title == "Telnet port 23 is open")
    }

    // MARK: - Each rule, and how device type moves severity

    struct Case: Sendable, CustomTestStringConvertible {
        let port: Int
        let type: DeviceType
        let rule: String
        let severity: SecuritySeverity
        var testDescription: String { "\(port) on \(type.rawValue) → \(rule) \(severity.label)" }
    }

    @Test(arguments: [
        Case(port: 23, type: .unknown, rule: "telnet", severity: .high),
        Case(port: 23, type: .router, rule: "telnet", severity: .high),
        Case(port: 21, type: .computer, rule: "ftp", severity: .medium),
        Case(port: 21, type: .storage, rule: "ftp", severity: .high),
        Case(port: 21, type: .camera, rule: "ftp", severity: .high),
        Case(port: 3389, type: .computer, rule: "rdp", severity: .medium),
        Case(port: 5900, type: .computer, rule: "vnc", severity: .medium),
        Case(port: 5900, type: .iot, rule: "vnc", severity: .high),
        Case(port: 6379, type: .computer, rule: "redis", severity: .high),
        Case(port: 27017, type: .unknown, rule: "mongodb", severity: .high),
        Case(port: 3306, type: .storage, rule: "mysql", severity: .medium),
        Case(port: 5432, type: .computer, rule: "postgresql", severity: .medium),
        Case(port: 445, type: .unknown, rule: "smb", severity: .medium),
        Case(port: 445, type: .storage, rule: "smb", severity: .low),
        Case(port: 445, type: .laptop, rule: "smb", severity: .low),
        Case(port: 80, type: .router, rule: "http-admin", severity: .medium),
        Case(port: 8080, type: .camera, rule: "http-admin", severity: .medium),
        Case(port: 80, type: .printer, rule: "http-admin", severity: .low),
        Case(port: 139, type: .computer, rule: "netbios", severity: .low),
        Case(port: 5000, type: .router, rule: "upnp", severity: .low),
        Case(port: 22, type: .camera, rule: "ssh-iot", severity: .low),
        Case(port: 22, type: .iot, rule: "ssh-iot", severity: .low)
    ])
    func rule(_ test: Case) {
        let findings = SecurityRuleTable.findings(for: [device("Device", test.type, ports: [test.port])])
        #expect(findings.map(\.ruleID) == [test.rule])
        #expect(findings.first?.severity == test.severity)
    }

    @Test("Type-limited rules don't fire on other types", arguments: [
        (22, DeviceType.computer), (22, .storage), (80, .phone), (80, .computer), (8080, .unknown),
        (5000, .computer), (5000, .unknown)
    ])
    func typeLimited(port: Int, type: DeviceType) {
        #expect(SecurityRuleTable.findings(for: [device("Device", type, ports: [port])]).isEmpty)
    }

    @Test func titlesStateTheMeasuredPort() {
        let ports = [23, 445, 80]
        let titles = SecurityRuleTable.findings(for: [device("Cam", .camera, ports: ports)]).map(\.title)
        #expect(titles == ["Telnet port 23 is open", "SMB file sharing port 445 is open", "HTTP admin page port 80 is open"])
    }

    @Test func theQuickScanPortsAreTheRulePorts() {
        #expect(SecurityRuleTable.ports == [21, 22, 23, 80, 139, 445, 3306, 3389, 5000, 5432, 5900, 6379, 8080, 27017])
    }

    // MARK: - Measured ports only

    @Test func noPortsMeasuredMeansNoFindings() {
        #expect(SecurityRuleTable.findings(for: [device("Never scanned", .camera, ports: nil)]).isEmpty)
        #expect(SecurityRuleTable.findings(for: [device("Nothing open", .camera, ports: [])]).isEmpty)
    }

    @Test func onlyMeasuredPortsProduceFindings() {
        // 443 and 9100 have no rule; 23 is the only rule port measured.
        let printer = device("Printer", .printer, ports: [443, 9100, 23, 23])
        let findings = SecurityRuleTable.findings(for: [printer])
        #expect(findings.map(\.port) == [23])
        #expect(findings.allSatisfy { [443, 9100, 23].contains($0.port) })
    }

    // MARK: - Ranking

    @Test func rankedBySeverityThenRuleThenName() {
        let nas = device("NAS", .storage, ports: [445, 21])
        let camera = device("Camera", .camera, ports: [80, 23])
        let router = device("Router", .router, ports: [23, 5000])
        let order = SecurityRuleTable.findings(for: [nas, camera, router]).map { "\($0.deviceName) \($0.port) \($0.severity.label)" }
        #expect(order == [
            "Camera 23 high", "Router 23 high", "NAS 21 high",
            "Camera 80 medium",
            "NAS 445 low", "Router 5000 low"
        ])
    }

    // MARK: - Identity

    @Test func aRenamedDeviceShowsItsNewName() {
        let camera = device("Garage Camera", .camera, ports: [23])
        let before = SecurityRuleTable.findings(for: [camera])
        camera.customName = "Driveway Camera"
        let after = SecurityRuleTable.findings(for: [camera])
        #expect(before.map(\.deviceName) == ["Garage Camera"])
        #expect(after.map(\.deviceName) == ["Driveway Camera"])
        #expect(after.map(\.deviceID) == [camera.id])
        #expect(after.map(\.id) == before.map(\.id))
    }
}
