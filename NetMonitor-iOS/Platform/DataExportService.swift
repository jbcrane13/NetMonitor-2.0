import Foundation
import NetMonitorCore
import SwiftData
import os

/// Service for exporting app data to JSON and CSV formats
enum DataExportService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "DataExportService")

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        case pdf = "PDF"

        var fileExtension: String {
            rawValue.lowercased()
        }

        var mimeType: String {
            switch self {
            case .json: "application/json"
            case .csv: "text/csv"
            case .pdf: "application/pdf"
            }
        }
    }

    // MARK: - PDF Report Export

    /// Generates a full-network PDF report combining devices, tool results, and speed tests.
    /// Where the on-device model is available it first writes an executive summary from the
    /// app's digest of the same records (#453); when it is unavailable, fails, takes longer
    /// than `summaryTimeout` or states a number not in the digest, the report has no summary page.
    @MainActor
    static func exportFullReportAsPDF(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult],
        insightService: any InsightServiceProtocol = PhoneInsight.shared,
        summaryTimeout: Duration = .seconds(20),
        now: Date = Date(),
        presence: PresenceSnapshot? = nil
    ) async -> Data? {
        var executiveSummary: PDFReportGenerator.ExecutiveSummary?
        if let request = ReportSummaryBuilder.request(devices: devices, toolResults: toolResults, speedTests: speedTests, now: now),
           let answer = await InsightSummarizer.outcome(for: request, service: insightService, timeout: summaryTimeout).answer {
            executiveSummary = PDFReportGenerator.ExecutiveSummary(text: answer.text, keyPoints: request.observations, source: answer.source)
        }
        return PDFReportGenerator.generateNetworkReport(
            devices: devices,
            toolResults: toolResults,
            speedTests: speedTests,
            presence: presence ?? SavedDeviceList.currentPresence(),
            executiveSummary: executiveSummary
        )
    }

    // MARK: - Tool Results Export

    static func exportToolResults(_ results: [ToolResult], format: ExportFormat) -> Data? {
        switch format {
        case .json:
            return exportToolResultsJSON(results)
        case .csv:
            return exportToolResultsCSV(results)
        case .pdf:
            return nil
        }
    }

    private static func exportToolResultsJSON(_ results: [ToolResult]) -> Data? {
        let items = results.map { result in
            [
                "id": result.id.uuidString,
                "toolType": result.toolType.rawValue,
                "target": result.target,
                "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                "duration": String(result.duration),
                "success": String(result.success),
                "summary": result.summary,
                "details": result.details,
                "errorMessage": result.errorMessage ?? ""
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportToolResultsCSV(_ results: [ToolResult]) -> Data? {
        var csv = "id,toolType,target,timestamp,duration,success,summary,details,errorMessage\n"
        let formatter = ISO8601DateFormatter()
        for result in results {
            csv += "\(csvEscape(result.id.uuidString)),\(csvEscape(result.toolType.rawValue)),\(csvEscape(result.target)),"
            csv += "\(csvEscape(formatter.string(from: result.timestamp))),\(result.duration),\(result.success),"
            csv += "\(csvEscape(result.summary)),\(csvEscape(result.details)),\(csvEscape(result.errorMessage ?? ""))\n"
        }
        return csv.data(using: .utf8)
    }

    // MARK: - Speed Test Results Export

    static func exportSpeedTests(_ results: [SpeedTestResult], format: ExportFormat) -> Data? {
        switch format {
        case .json:
            return exportSpeedTestsJSON(results)
        case .csv:
            return exportSpeedTestsCSV(results)
        case .pdf:
            return nil
        }
    }

    private static func exportSpeedTestsJSON(_ results: [SpeedTestResult]) -> Data? {
        let items = results.map { result in
            [
                "id": result.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                "downloadSpeed": String(result.downloadSpeed),
                "uploadSpeed": String(result.uploadSpeed),
                "latency": String(result.latency),
                "jitter": result.jitter.map { String($0) } ?? "",
                "serverName": result.serverName ?? "",
                "connectionType": result.connectionType.rawValue,
                "success": String(result.success)
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportSpeedTestsCSV(_ results: [SpeedTestResult]) -> Data? {
        var csv = "id,timestamp,downloadSpeed,uploadSpeed,latency,jitter,serverName,connectionType,success\n"
        let formatter = ISO8601DateFormatter()
        for result in results {
            csv += "\(csvEscape(result.id.uuidString)),\(csvEscape(formatter.string(from: result.timestamp))),"
            csv += "\(result.downloadSpeed),\(result.uploadSpeed),\(result.latency),"
            csv += "\(result.jitter.map { String($0) } ?? ""),\(csvEscape(result.serverName ?? "")),"
            csv += "\(csvEscape(result.connectionType.rawValue)),\(result.success)\n"
        }
        return csv.data(using: .utf8)
    }

    // MARK: - Devices Export

    static func exportDevices(_ devices: [LocalDevice], format: ExportFormat) -> Data? {
        switch format {
        case .json:
            return exportDevicesJSON(devices)
        case .csv:
            return exportDevicesCSV(devices)
        case .pdf:
            return nil
        }
    }

    /// The `hostname` and `vendor` columns keep what they held before friendly names and
    /// announced makers moved to their own fields (ADR-022): the hostname, else the friendly
    /// name; the MAC-prefix maker, else the announced or guessed maker.
    private static func exportedHostname(_ device: LocalDevice) -> String {
        [device.hostname, device.friendlyName].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    private static func exportedVendor(_ device: LocalDevice) -> String {
        [device.vendor, device.manufacturer].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    private static func exportDevicesJSON(_ devices: [LocalDevice]) -> Data? {
        let items = devices.map { device in
            [
                "id": device.id.uuidString,
                "ipAddress": device.ipAddress,
                "macAddress": device.macAddress,
                "hostname": exportedHostname(device),
                "vendor": exportedVendor(device),
                "deviceType": device.deviceType.rawValue,
                "customName": device.customName ?? "",
                "status": device.status.rawValue,
                "lastLatency": device.lastLatency.map { String($0) } ?? "",
                "isGateway": String(device.isGateway),
                "firstSeen": ISO8601DateFormatter().string(from: device.firstSeen),
                "lastSeen": ISO8601DateFormatter().string(from: device.lastSeen)
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportDevicesCSV(_ devices: [LocalDevice]) -> Data? {
        var csv = "id,ipAddress,macAddress,hostname,vendor,deviceType,customName,status,lastLatency,isGateway,firstSeen,lastSeen\n"
        let formatter = ISO8601DateFormatter()
        for device in devices {
            csv += "\(csvEscape(device.id.uuidString)),\(csvEscape(device.ipAddress)),\(csvEscape(device.macAddress)),"
            csv += "\(csvEscape(exportedHostname(device))),\(csvEscape(exportedVendor(device))),\(csvEscape(device.deviceType.rawValue)),"
            csv += "\(csvEscape(device.customName ?? "")),\(csvEscape(device.status.rawValue)),"
            csv += "\(device.lastLatency.map { String($0) } ?? ""),\(device.isGateway),"
            csv += "\(csvEscape(formatter.string(from: device.firstSeen))),\(csvEscape(formatter.string(from: device.lastSeen)))\n"
        }
        return csv.data(using: .utf8)
    }

    // MARK: - Helpers

    /// Quotes a CSV cell, and neutralizes one a spreadsheet would read as a formula: names and
    /// makers come from devices on the network, so a leading `=`, `+`, `-`, `@`, tab or carriage
    /// return gets an apostrophe in front (OWASP CSV injection).
    static func csvEscape(_ value: String) -> String {
        var value = value
        if let first = value.first, ["=", "+", "-", "@", "\t", "\r"].contains(first) {
            value = "'" + value
        }
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    static func writeToTempFile(data: Data, name: String, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            logger.error("Failed to write export file: \(error)")
            return nil
        }
    }
}
