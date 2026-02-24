import Foundation
import NetMonitorCore
import SwiftData
import os

/// Service for exporting app data to JSON and CSV formats
enum DataExportService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "DataExportService")

    enum ExportFormat: String, CaseIterable, Sendable {
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
    static func exportFullReportAsPDF(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult]
    ) -> Data? {
        PDFReportGenerator.generateNetworkReport(
            devices: devices,
            toolResults: toolResults,
            speedTests: speedTests
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
        let items = results.map { r in
            [
                "id": r.id.uuidString,
                "toolType": r.toolType.rawValue,
                "target": r.target,
                "timestamp": ISO8601DateFormatter().string(from: r.timestamp),
                "duration": String(r.duration),
                "success": String(r.success),
                "summary": r.summary,
                "details": r.details,
                "errorMessage": r.errorMessage ?? ""
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportToolResultsCSV(_ results: [ToolResult]) -> Data? {
        var csv = "id,toolType,target,timestamp,duration,success,summary,details,errorMessage\n"
        let formatter = ISO8601DateFormatter()
        for r in results {
            csv += "\(csvEscape(r.id.uuidString)),\(csvEscape(r.toolType.rawValue)),\(csvEscape(r.target)),"
            csv += "\(csvEscape(formatter.string(from: r.timestamp))),\(r.duration),\(r.success),"
            csv += "\(csvEscape(r.summary)),\(csvEscape(r.details)),\(csvEscape(r.errorMessage ?? ""))\n"
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
        let items = results.map { r in
            [
                "id": r.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: r.timestamp),
                "downloadSpeed": String(r.downloadSpeed),
                "uploadSpeed": String(r.uploadSpeed),
                "latency": String(r.latency),
                "jitter": r.jitter.map { String($0) } ?? "",
                "serverName": r.serverName ?? "",
                "connectionType": r.connectionType.rawValue,
                "success": String(r.success)
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportSpeedTestsCSV(_ results: [SpeedTestResult]) -> Data? {
        var csv = "id,timestamp,downloadSpeed,uploadSpeed,latency,jitter,serverName,connectionType,success\n"
        let formatter = ISO8601DateFormatter()
        for r in results {
            csv += "\(csvEscape(r.id.uuidString)),\(csvEscape(formatter.string(from: r.timestamp))),"
            csv += "\(r.downloadSpeed),\(r.uploadSpeed),\(r.latency),"
            csv += "\(r.jitter.map { String($0) } ?? ""),\(csvEscape(r.serverName ?? "")),"
            csv += "\(csvEscape(r.connectionType.rawValue)),\(r.success)\n"
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

    private static func exportDevicesJSON(_ devices: [LocalDevice]) -> Data? {
        let items = devices.map { d in
            [
                "id": d.id.uuidString,
                "ipAddress": d.ipAddress,
                "macAddress": d.macAddress,
                "hostname": d.hostname ?? "",
                "vendor": d.vendor ?? "",
                "deviceType": d.deviceType.rawValue,
                "customName": d.customName ?? "",
                "status": d.status.rawValue,
                "lastLatency": d.lastLatency.map { String($0) } ?? "",
                "isGateway": String(d.isGateway),
                "firstSeen": ISO8601DateFormatter().string(from: d.firstSeen),
                "lastSeen": ISO8601DateFormatter().string(from: d.lastSeen)
            ]
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    private static func exportDevicesCSV(_ devices: [LocalDevice]) -> Data? {
        var csv = "id,ipAddress,macAddress,hostname,vendor,deviceType,customName,status,lastLatency,isGateway,firstSeen,lastSeen\n"
        let formatter = ISO8601DateFormatter()
        for d in devices {
            csv += "\(csvEscape(d.id.uuidString)),\(csvEscape(d.ipAddress)),\(csvEscape(d.macAddress)),"
            csv += "\(csvEscape(d.hostname ?? "")),\(csvEscape(d.vendor ?? "")),\(csvEscape(d.deviceType.rawValue)),"
            csv += "\(csvEscape(d.customName ?? "")),\(csvEscape(d.status.rawValue)),"
            csv += "\(d.lastLatency.map { String($0) } ?? ""),\(d.isGateway),"
            csv += "\(csvEscape(formatter.string(from: d.firstSeen))),\(csvEscape(formatter.string(from: d.lastSeen)))\n"
        }
        return csv.data(using: .utf8)
    }

    // MARK: - Helpers

    private static func csvEscape(_ value: String) -> String {
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
