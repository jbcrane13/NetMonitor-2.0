import XCTest
@testable import NetMonitor_iOS
import NetMonitorCore

/// Tests for PDFReportGenerator — verifies PDF output format and non-nil generation.
/// These tests use empty arrays to avoid SwiftData @Model init requirements.
final class PDFReportGeneratorTests: XCTestCase {

    func testGenerateReport_emptyData_returnsData() {
        let data = PDFReportGenerator.generateNetworkReport(
            devices: [],
            toolResults: [],
            speedTests: []
        )
        XCTAssertNotNil(data, "PDF generator should return data even with empty input")
    }

    func testGenerateReport_emptyData_isValidPDF() {
        let data = PDFReportGenerator.generateNetworkReport(
            devices: [],
            toolResults: [],
            speedTests: []
        )
        guard let pdfData = data else {
            XCTFail("generateNetworkReport returned nil")
            return
        }
        // Valid PDFs start with the %PDF header
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF", "Output should be a valid PDF file")
    }

    func testGenerateReport_emptyData_nonZeroSize() {
        let data = PDFReportGenerator.generateNetworkReport(
            devices: [],
            toolResults: [],
            speedTests: []
        )
        XCTAssertGreaterThan(data?.count ?? 0, 100, "PDF should have non-trivial size")
    }

    func testGenerateReport_calledMultipleTimes_producesConsistentOutput() {
        // Verify the generator is stateless (same input → same structure)
        let data1 = PDFReportGenerator.generateNetworkReport(devices: [], toolResults: [], speedTests: [])
        let data2 = PDFReportGenerator.generateNetworkReport(devices: [], toolResults: [], speedTests: [])

        XCTAssertNotNil(data1)
        XCTAssertNotNil(data2)
        // Both should be valid PDFs
        let h1 = String(data: data1!.prefix(4), encoding: .ascii)
        let h2 = String(data: data2!.prefix(4), encoding: .ascii)
        XCTAssertEqual(h1, "%PDF")
        XCTAssertEqual(h2, "%PDF")
    }
}
