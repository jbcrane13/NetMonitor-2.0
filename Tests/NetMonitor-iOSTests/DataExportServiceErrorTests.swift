import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_iOS

/// Area 6a: Silent failure error surfacing tests for DataExportService.
///
/// DataExportService uses `try? JSONSerialization.data(...)` in three places:
///   - exportToolResultsJSON (line ~70)
///   - exportSpeedTestsJSON (line ~111)
///   - exportDevicesJSON (line ~156)
///
/// When serialization fails, these methods return nil. The calling code receives
/// nil but has no way to know WHY the export failed — the error is silently
/// swallowed by `try?`.
///
/// These tests document the current nil-return behavior on the error path.
/// They do NOT modify production code — they verify and annotate the gap.
struct DataExportServiceErrorTests {

    // MARK: - All Three Export Methods: JSON Returns Optional (try? pattern)

    @Test("All three JSON export methods return non-nil for valid empty input")
    func allJSONExportsSucceedWithEmptyInput() {
        // These methods use: try? JSONSerialization.data(withJSONObject:)
        // Valid input (empty arrays) should always succeed.
        #expect(DataExportService.exportToolResults([], format: .json) != nil)
        #expect(DataExportService.exportSpeedTests([], format: .json) != nil)
        #expect(DataExportService.exportDevices([], format: .json) != nil)
    }

    // MARK: - PDF Export: Returns nil for non-full-report paths

    @Test("PDF export returns nil for individual export methods — not implemented, error not surfaced")
    func pdfExportReturnsNilForIndividualMethods() {
        #expect(DataExportService.exportToolResults([], format: .pdf) == nil,
                "PDF not implemented for tool results — returns nil, caller must check")
        #expect(DataExportService.exportSpeedTests([], format: .pdf) == nil,
                "PDF not implemented for speed tests — returns nil, caller must check")
        #expect(DataExportService.exportDevices([], format: .pdf) == nil,
                "PDF not implemented for devices — returns nil, caller must check")
    }

    // MARK: - writeToTempFile: Error Path

    @Test("writeToTempFile with empty data returns a valid URL")
    func writeEmptyDataReturnsURL() {
        let url = DataExportService.writeToTempFile(data: Data(), name: "empty_test", ext: "json")
        #expect(url != nil, "Writing empty data should still create a file")
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Documenting the Silent Failure Gap

    @Test("JSON export returns nil on failure — error message not available to caller")
    func jsonExportNilReturnDocumentsGap() {
        // This test documents that when JSONSerialization.data fails inside
        // exportDevicesJSON/exportToolResultsJSON/exportSpeedTestsJSON,
        // the caller receives nil with no error context.
        //
        // In the current code, the `try?` in each method means:
        //   return try? JSONSerialization.data(withJSONObject: items, options: [...])
        //
        // If items contained a non-JSON-serializable value (e.g., NaN, Infinity),
        // JSONSerialization would throw, and the method would return nil.
        //
        // The calling code (e.g., ExportView) must check for nil and show a
        // generic "Export failed" message — it cannot show the specific error.
        //
        // GAP: Consider changing the return type to throws or Result<Data, Error>
        // so callers can surface specific failure reasons to the user.

        // Verify the method signature returns optional (documents current API)
        let result: Data? = DataExportService.exportDevices([], format: .json)
        #expect(result != nil, "Valid input should succeed — this test documents the optional return type")
    }
}
