import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for PortScannerService state management and PortScanResult / PortScanPreset logic.
/// Network-dependent port scanning (NWConnection) is excluded.
@Suite("PortScannerService")
struct PortScannerServiceTests {

    // MARK: - State management

    @Test("stop() is safe to call before any scan")
    func stopSafeBeforeAnyScan() async {
        let service = PortScannerService()
        await service.stop()
        // Should not crash
        #expect(true)
    }

    @Test("stop() is idempotent")
    func stopIsIdempotent() async {
        let service = PortScannerService()
        await service.stop()
        await service.stop()
        await service.stop()
        #expect(true)
    }

    // MARK: - PortScanPreset port lists

    @Test("common preset contains expected ports")
    func commonPresetContainsExpectedPorts() {
        let ports = PortScanPreset.common.ports
        #expect(ports.contains(22))
        #expect(ports.contains(80))
        #expect(ports.contains(443))
        #expect(ports.contains(3306))
        #expect(!ports.isEmpty)
    }

    @Test("web preset contains HTTP and HTTPS ports")
    func webPresetContainsHTTPPorts() {
        let ports = PortScanPreset.web.ports
        #expect(ports.contains(80))
        #expect(ports.contains(443))
        #expect(ports.contains(8080))
        #expect(ports.contains(8443))
    }

    @Test("database preset contains major database ports")
    func databasePresetContainsMajorDatabasePorts() {
        let ports = PortScanPreset.database.ports
        #expect(ports.contains(3306))   // MySQL
        #expect(ports.contains(5432))   // PostgreSQL
        #expect(ports.contains(6379))   // Redis
        #expect(ports.contains(27017))  // MongoDB
    }

    @Test("mail preset contains SMTP and IMAP ports")
    func mailPresetContainsMailPorts() {
        let ports = PortScanPreset.mail.ports
        #expect(ports.contains(25))    // SMTP
        #expect(ports.contains(587))   // Submission
        #expect(ports.contains(993))   // IMAPS
        #expect(ports.contains(995))   // POP3S
    }

    @Test("custom preset returns empty port list")
    func customPresetReturnsEmptyList() {
        #expect(PortScanPreset.custom.ports.isEmpty)
    }

    @Test("custom preset isCustom is true")
    func customPresetIsCustomTrue() {
        #expect(PortScanPreset.custom.isCustom == true)
    }

    @Test("non-custom preset isCustom is false")
    func nonCustomPresetIsCustomFalse() {
        #expect(PortScanPreset.common.isCustom == false)
        #expect(PortScanPreset.web.isCustom == false)
    }

    @Test("wellKnown preset covers ports 1 through 1024")
    func wellKnownPresetCovers1To1024() {
        let ports = PortScanPreset.wellKnown.ports
        #expect(ports.first == 1)
        #expect(ports.last == 1024)
        #expect(ports.count == 1024)
    }

    // MARK: - PortRange

    @Test("PortRange with valid start/end is valid")
    func portRangeValidWhenStartLessThanEnd() {
        let range = PortRange(start: 80, end: 443)
        #expect(range.isValid == true)
        #expect(range.count == 364)
    }

    @Test("PortRange with start == end is valid")
    func portRangeSinglePortIsValid() {
        let range = PortRange(start: 443, end: 443)
        #expect(range.isValid == true)
        #expect(range.count == 1)
        #expect(range.ports == [443])
    }

    @Test("PortRange with start > end is invalid")
    func portRangeInvalidWhenStartGreaterThanEnd() {
        let range = PortRange(start: 1000, end: 500)
        #expect(range.isValid == false)
        #expect(range.ports.isEmpty)
        #expect(range.count == 0)
    }

    @Test("PortRange clamps values to valid port range")
    func portRangeClampsValues() {
        // start=0 should clamp to 1
        let range = PortRange(start: 0, end: 100)
        #expect(range.start == 1)
    }
}
