import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - DataExportService Extended Tests
//
// The existing DataExportServiceTests.swift covers format metadata and
// empty-array exports. This suite adds tests for:
//   - CSV header correctness (all expected column names present)
//   - CSV field escaping (commas, embedded quotes)
//   - JSON valid output (parseable, correct field presence)
//   - Empty data handling for all entity types

struct DataExportServiceExtendedTests {

    // MARK: - Helpers

    private func makeDevice(
        ipAddress: String = "192.168.1.100",
        macAddress: String = "AA:BB:CC:DD:EE:FF",
        hostname: String? = "myhost",
        vendor: String? = "Apple Inc.",
        customName: String? = nil
    ) -> LocalDevice {
        let d = LocalDevice(ipAddress: ipAddress, macAddress: macAddress)
        d.hostname = hostname
        d.vendor = vendor
        d.customName = customName
        return d
    }

    // MARK: - CSV Header Correctness

    @Test func toolResultsCSVHeaderContainsAllExpectedColumns() {
        let data = DataExportService.exportToolResults([], format: .csv)!
        let header = String(data: data, encoding: .utf8)!.components(separatedBy: "\n").first ?? ""
        let expectedColumns = ["id", "toolType", "target", "timestamp", "duration",
                               "success", "summary", "details", "errorMessage"]
        for col in expectedColumns {
            #expect(header.contains(col), "Missing column: \(col)")
        }
    }

    @Test func speedTestsCSVHeaderContainsAllExpectedColumns() {
        let data = DataExportService.exportSpeedTests([], format: .csv)!
        let header = String(data: data, encoding: .utf8)!.components(separatedBy: "\n").first ?? ""
        let expectedColumns = ["id", "timestamp", "downloadSpeed", "uploadSpeed",
                               "latency", "jitter", "serverName", "connectionType", "success"]
        for col in expectedColumns {
            #expect(header.contains(col), "Missing column: \(col)")
        }
    }

    @Test func devicesCSVHeaderContainsAllExpectedColumns() {
        let data = DataExportService.exportDevices([], format: .csv)!
        let header = String(data: data, encoding: .utf8)!.components(separatedBy: "\n").first ?? ""
        let expectedColumns = ["id", "ipAddress", "macAddress", "hostname", "vendor",
                               "deviceType", "customName", "status", "lastLatency",
                               "isGateway", "firstSeen", "lastSeen"]
        for col in expectedColumns {
            #expect(header.contains(col), "Missing column: \(col)")
        }
    }

    // MARK: - CSV Field Escaping

    @Test func csvEscapesCommasInDeviceHostname() {
        // hostname with a comma should be quoted in CSV output
        let device = makeDevice(hostname: "printer, office")
        let data = DataExportService.exportDevices([device], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        // The hostname value containing a comma must be wrapped in double-quotes
        #expect(csv.contains("\"printer, office\""))
    }

    @Test func csvEscapesDoubleQuotesInDeviceVendor() {
        // vendor name containing a double-quote should use doubled-quote escaping
        let device = makeDevice(vendor: "Acme \"Corp\" Ltd")
        let data = DataExportService.exportDevices([device], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        // RFC 4180: embedded quotes are doubled
        #expect(csv.contains("\"Acme \"\"Corp\"\" Ltd\""))
    }

    @Test func csvFieldWithoutSpecialCharsIsNotQuoted() {
        let device = makeDevice(hostname: "router")
        let data = DataExportService.exportDevices([device], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        // "router" has no special characters, so it should appear unquoted
        #expect(csv.contains("router"))
        // It must not be surrounded by quotes on its own
        #expect(!csv.contains("\"router\""))
    }

    // MARK: - JSON Valid Output

    @Test func devicesJSONIsValidAndParseable() {
        let device = makeDevice()
        let data = DataExportService.exportDevices([device], format: .json)
        #expect(data != nil)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [[String: String]]
        #expect(parsed != nil)
        #expect(parsed?.count == 1)
    }

    @Test func devicesJSONContainsExpectedFields() {
        let device = makeDevice(ipAddress: "10.0.0.5", macAddress: "11:22:33:44:55:66")
        let data = DataExportService.exportDevices([device], format: .json)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        let record = parsed?.first
        #expect(record?["ipAddress"] == "10.0.0.5")
        #expect(record?["macAddress"] == "11:22:33:44:55:66")
        #expect(record?["hostname"] == "myhost")
    }

    @Test func speedTestsJSONIsValidAndParseable() {
        let data = DataExportService.exportSpeedTests([], format: .json)
        #expect(data != nil)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [[String: String]]
        #expect(parsed?.isEmpty == true)
    }

    // MARK: - Empty Data Handling

    @Test func exportEmptyDevicesCSVProducesOnlyHeaderLine() {
        let data = DataExportService.exportDevices([], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        // Should have header line + trailing newline, no data rows
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }

    @Test func exportEmptyToolResultsCSVProducesOnlyHeaderLine() {
        let data = DataExportService.exportToolResults([], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }

    @Test func exportEmptySpeedTestsCSVProducesOnlyHeaderLine() {
        let data = DataExportService.exportSpeedTests([], format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }

    @Test func pdfFormatReturnsNilForToolResults() {
        // PDF export is not implemented for tool results
        let result = DataExportService.exportToolResults([], format: .pdf)
        #expect(result == nil)
    }

    @Test func pdfFormatReturnsNilForSpeedTests() {
        let result = DataExportService.exportSpeedTests([], format: .pdf)
        #expect(result == nil)
    }

    @Test func pdfFormatReturnsNilForDevices() {
        let result = DataExportService.exportDevices([], format: .pdf)
        #expect(result == nil)
    }
}
