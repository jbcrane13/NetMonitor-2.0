import XCTest
import PDFKit
@testable import NetMonitor_iOS
import NetMonitorCore

/// An insight service that answers every request at once with `answer`, and records requests.
private final class ReportInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [InsightRequest] = []
    let isAvailable: Bool
    let answer: String

    init(isAvailable: Bool, answer: String = "") {
        self.isAvailable = isAvailable
        self.answer = answer
    }

    var requests: [InsightRequest] { lock.withLock { received } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        lock.withLock { received.append(request) }
        return AsyncStream { continuation in
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }
}

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

    // MARK: - Executive summary (#453)

    private func pages(_ data: Data?) -> Int {
        data.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0
    }

    private func text(_ data: Data?) -> String {
        data.flatMap { PDFDocument(data: $0)?.string } ?? ""
    }

    /// Records with one offline device, so the digest has a key point.
    private func records() -> ([LocalDevice], [ToolResult], [SpeedTestResult]) {
        let devices = [
            LocalDevice(ipAddress: "192.168.1.1", macAddress: "", customName: "Router"),
            LocalDevice(ipAddress: "192.168.1.40", macAddress: "", customName: "Printer", status: .offline)
        ]
        let results = [ToolResult(toolType: .ping, target: "192.168.1.1", success: true, summary: "4 ms")]
        return (devices, results, [SpeedTestResult(downloadSpeed: 412, uploadSpeed: 38, latency: 14)])
    }

    func testExecutiveSummaryAddsOnePageWithTheKeyPointsAndText() {
        let summary = PDFReportGenerator.ExecutiveSummary(text: "One of the 2 devices is offline.", keyPoints: ["1 device is offline."])
        let without = PDFReportGenerator.generateNetworkReport(devices: [], toolResults: [], speedTests: [])
        let with = PDFReportGenerator.generateNetworkReport(devices: [], toolResults: [], speedTests: [], executiveSummary: summary)

        XCTAssertEqual(pages(with), pages(without) + 1)
        let firstPage = PDFDocument(data: with ?? Data())?.page(at: 0)?.string ?? ""
        XCTAssertTrue(firstPage.contains("Executive Summary"))
        XCTAssertTrue(firstPage.contains("1 device is offline."))
        XCTAssertTrue(firstPage.contains("Written by the on-device model"))
        XCTAssertTrue(firstPage.contains("One of the 2 devices is offline."))
    }

    func testWithoutSummaryThePageCountIsUnchanged() {
        let (devices, results, tests) = records()
        XCTAssertEqual(pages(PDFReportGenerator.generateNetworkReport(devices: [], toolResults: [], speedTests: [])), 1)
        XCTAssertEqual(
            pages(PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: results, speedTests: tests, executiveSummary: nil)),
            pages(PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: results, speedTests: tests))
        )
        let plain = PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: results, speedTests: tests)
        XCTAssertFalse(text(plain).contains("Executive Summary"))
    }

    @MainActor
    func testExportWithTheModelUnavailableHasNoSummaryPage() async {
        let (devices, results, tests) = records()
        let service = ReportInsightService(isAvailable: false, answer: "1 device is offline.")
        let data = await DataExportService.exportFullReportAsPDF(
            devices: devices, toolResults: results, speedTests: tests, insightService: service
        )
        let plain = PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: results, speedTests: tests)

        XCTAssertEqual(pages(data), pages(plain))
        XCTAssertFalse(text(data).contains("Executive Summary"))
        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testExportWithTheModelAnsweringStartsWithTheSummaryPage() async {
        let (devices, results, tests) = records()
        let service = ReportInsightService(isAvailable: true, answer: "One of the 2 devices is offline; the latest download was 412.0 Mbps.")
        let data = await DataExportService.exportFullReportAsPDF(
            devices: devices, toolResults: results, speedTests: tests, insightService: service
        )
        let plain = PDFReportGenerator.generateNetworkReport(devices: devices, toolResults: results, speedTests: tests)

        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests.first?.kind, .summary)
        XCTAssertTrue(service.requests.first?.facts.contains("Number of devices: 2") == true)
        XCTAssertEqual(pages(data), pages(plain) + 1)
        let firstPage = PDFDocument(data: data ?? Data())?.page(at: 0)?.string ?? ""
        XCTAssertTrue(firstPage.contains("1 device is offline."))
        XCTAssertTrue(firstPage.contains("One of the 2 devices is offline; the latest download was 412.0 Mbps."))
    }

    @MainActor
    func testExportDropsAnAnswerWithANumberNotInTheReport() async {
        let (devices, results, tests) = records()
        let service = ReportInsightService(isAvailable: true, answer: "Three devices are offline.")
        let data = await DataExportService.exportFullReportAsPDF(
            devices: devices, toolResults: results, speedTests: tests, insightService: service
        )
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertFalse(text(data).contains("Executive Summary"))
    }
}
