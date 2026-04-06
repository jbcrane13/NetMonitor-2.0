import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// Additional DataExportService tests for gaps not covered by
/// DataExportServiceTests or DataExportServiceExtendedTests:
/// - PDF format metadata
/// - Multi-record CSV row count
/// - CSV field correctness with real data
/// - writeToTempFile cleanup and overwrite behavior

struct DataExportServiceAdditionalTests {

    // MARK: - PDF format metadata

    @Test("ExportFormat.pdf has correct file extension and MIME type")
    func pdfFormatMetadata() {
        let pdf = DataExportService.ExportFormat.pdf
        #expect(pdf.fileExtension == "pdf")
        #expect(pdf.mimeType == "application/pdf")
        #expect(pdf.rawValue == "PDF")
    }

    // MARK: - Multi-record CSV

    @Test("Devices CSV has correct number of data rows for multiple devices")
    func multiDeviceCSVRowCount() {
        let devices = (0..<5).map { i in
            let d = LocalDevice(ipAddress: "192.168.1.\(i)", macAddress: "AA:BB:CC:DD:EE:\(String(format: "%02X", i))")
            d.hostname = "host-\(i)"
            return d
        }

        let data = DataExportService.exportDevices(devices, format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        let nonEmptyLines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        // 1 header + 5 data rows
        #expect(nonEmptyLines.count == 6)
    }

    @Test("Speed tests CSV has correct number of data rows")
    func multiSpeedTestCSVRowCount() {
        var results: [SpeedTestResult] = []
        for i in 0..<3 {
            let result = SpeedTestResult(
                downloadSpeed: Double(i * 100),
                uploadSpeed: Double(i * 50),
                latency: Double(i * 10),
                success: true
            )
            results.append(result)
        }

        let data = DataExportService.exportSpeedTests(results, format: .csv)!
        let csv = String(data: data, encoding: .utf8)!
        let nonEmptyLines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(nonEmptyLines.count == 4) // 1 header + 3 data
    }

    // MARK: - Multi-record JSON

    @Test("Devices JSON array count matches input")
    func multiDeviceJSONCount() {
        let devices = (0..<4).map { i in
            LocalDevice(ipAddress: "10.0.0.\(i)", macAddress: "00:00:00:00:00:\(String(format: "%02X", i))")
        }

        let data = DataExportService.exportDevices(devices, format: .json)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        #expect(parsed?.count == 4)
    }

    // MARK: - writeToTempFile overwrite behavior

    @Test("writeToTempFile overwrites existing file at same path")
    func writeToTempFileOverwrites() throws {
        let first = "first content".data(using: .utf8)!
        let second = "second content".data(using: .utf8)!

        let url1 = DataExportService.writeToTempFile(data: first, name: "overwrite_test", ext: "txt")
        #expect(url1 != nil)

        let url2 = DataExportService.writeToTempFile(data: second, name: "overwrite_test", ext: "txt")
        #expect(url2 != nil)

        let content = try String(contentsOf: url2!, encoding: .utf8)
        #expect(content == "second content")

        // Cleanup
        try? FileManager.default.removeItem(at: url2!)
    }

    // MARK: - Speed test JSON field presence

    @Test("Speed test JSON includes all expected fields")
    func speedTestJSONFieldPresence() {
        let result = SpeedTestResult(
            downloadSpeed: 100.5,
            uploadSpeed: 50.2,
            latency: 15.0,
            success: true
        )

        let data = DataExportService.exportSpeedTests([result], format: .json)!
        let parsed = (try? JSONSerialization.jsonObject(with: data) as? [[String: String]])?.first
        #expect(parsed != nil)
        #expect(parsed?["downloadSpeed"] != nil)
        #expect(parsed?["uploadSpeed"] != nil)
        #expect(parsed?["latency"] != nil)
        #expect(parsed?["success"] == "true")
    }
}
