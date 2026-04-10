import Foundation
import Testing
@testable import NetMonitor_iOS

struct DataExportServiceTests {

    // MARK: - ExportFormat

    @Test func exportFormatFileExtensions() {
        #expect(DataExportService.ExportFormat.json.fileExtension == "json")
        #expect(DataExportService.ExportFormat.csv.fileExtension == "csv")
    }

    @Test func exportFormatMimeTypes() {
        #expect(DataExportService.ExportFormat.json.mimeType == "application/json")
        #expect(DataExportService.ExportFormat.csv.mimeType == "text/csv")
    }

    @Test func exportFormatRawValues() {
        #expect(DataExportService.ExportFormat.json.rawValue == "JSON")
        #expect(DataExportService.ExportFormat.csv.rawValue == "CSV")
    }

    @Test func exportFormatAllCasesCount() {
        #expect(DataExportService.ExportFormat.allCases.count == 3)
    }

    // MARK: - Tool Results Export (empty array)

    @Test func exportEmptyToolResultsCSVHasHeader() {
        let data = DataExportService.exportToolResults([], format: .csv)
        #expect(data != nil)
        let string = String(data: data!, encoding: .utf8) ?? ""
        #expect(string.hasPrefix("id,toolType,target,timestamp,duration,success,summary,details,errorMessage"))
    }

    @Test func exportEmptyToolResultsJSONIsEmptyArray() {
        let data = DataExportService.exportToolResults([], format: .json)
        #expect(data != nil)
        let array = try? JSONSerialization.jsonObject(with: data!) as? [[String: String]]
        #expect(array?.isEmpty == true)
    }

    // MARK: - Speed Test Results Export (empty array)

    @Test func exportEmptySpeedTestsCSVHasHeader() {
        let data = DataExportService.exportSpeedTests([], format: .csv)
        #expect(data != nil)
        let string = String(data: data!, encoding: .utf8) ?? ""
        #expect(string.hasPrefix("id,timestamp,downloadSpeed,uploadSpeed,latency"))
    }

    @Test func exportEmptySpeedTestsJSONIsEmptyArray() {
        let data = DataExportService.exportSpeedTests([], format: .json)
        #expect(data != nil)
        let array = try? JSONSerialization.jsonObject(with: data!) as? [[String: String]]
        #expect(array?.isEmpty == true)
    }

    // MARK: - Devices Export (empty array)

    @Test func exportEmptyDevicesCSVHasHeader() {
        let data = DataExportService.exportDevices([], format: .csv)
        #expect(data != nil)
        let string = String(data: data!, encoding: .utf8) ?? ""
        #expect(string.hasPrefix("id,ipAddress,macAddress,hostname,vendor,deviceType"))
    }

    @Test func exportEmptyDevicesJSONIsEmptyArray() {
        let data = DataExportService.exportDevices([], format: .json)
        #expect(data != nil)
        let array = try? JSONSerialization.jsonObject(with: data!) as? [[String: String]]
        #expect(array?.isEmpty == true)
    }

    // MARK: - writeToTempFile

    @Test func writeToTempFileCreatesFile() {
        let content = "test content"
        let data = content.data(using: .utf8)!
        let url = DataExportService.writeToTempFile(data: data, name: "test_export", ext: "txt")
        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func writeToTempFileReturnsCorrectExtension() {
        let data = "{}".data(using: .utf8)!
        let url = DataExportService.writeToTempFile(data: data, name: "export", ext: "json")
        #expect(url?.pathExtension == "json")
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    @Test func writeToTempFileContainsCorrectData() throws {
        let expected = "hello,world"
        let data = expected.data(using: .utf8)!
        guard let url = DataExportService.writeToTempFile(data: data, name: "csv_test", ext: "csv") else {
            #expect(Bool(false), "writeToTempFile returned nil")
            return
        }
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == expected)
        try? FileManager.default.removeItem(at: url)
    }
}
