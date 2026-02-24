import UIKit
import NetMonitorCore

/// Builds formatted PDF network reports using UIGraphicsPDFRenderer.
public enum PDFReportGenerator {

    // MARK: - Layout constants

    private static let pageWidth: CGFloat = 612   // US Letter width (pts)
    private static let pageHeight: CGFloat = 792  // US Letter height (pts)
    private static let margin: CGFloat = 40
    private static let contentWidth: CGFloat = pageWidth - margin * 2
    private static let rowHeight: CGFloat = 16
    private static let sectionGap: CGFloat = 20

    private static let headerBlue = UIColor(red: 0.05, green: 0.10, blue: 0.28, alpha: 1.0)
    private static let tableBlue  = UIColor(red: 0.10, green: 0.20, blue: 0.50, alpha: 1.0)
    private static let stripeFill = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)

    // MARK: - Public API

    /// Generates a full network PDF report from provided data arrays.
    /// - Returns: PDF data, or nil if rendering fails.
    public static func generateNetworkReport(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult]
    ) -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = drawHeader()
            y = drawSummary(devices: devices, speedTests: speedTests, y: y)

            if !devices.isEmpty {
                y = drawDevices(devices: devices, ctx: ctx, y: y)
            }
            if !toolResults.isEmpty {
                y = drawToolResults(toolResults: toolResults, ctx: ctx, y: y)
            }
            if !speedTests.isEmpty {
                _ = drawSpeedTests(speedTests: speedTests, ctx: ctx, y: y)
            }
            drawFooter()
        }
    }

    // MARK: - Header / Footer

    @discardableResult
    private static func drawHeader() -> CGFloat {
        // Background
        headerBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: 80))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.white
        ]
        "NetMonitor Pro · Network Report".draw(
            at: CGPoint(x: margin, y: 22),
            withAttributes: titleAttrs
        )

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor(white: 0.75, alpha: 1.0)
        ]
        let dateStr = "Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        dateStr.draw(at: CGPoint(x: margin, y: 52), withAttributes: dateAttrs)

        return 100
    }

    private static func drawFooter() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.lightGray
        ]
        "NetMonitor Pro  ·  Network Diagnostic Report".draw(
            at: CGPoint(x: margin, y: pageHeight - 28),
            withAttributes: attrs
        )
    }

    // MARK: - Summary Section

    private static func drawSummary(devices: [LocalDevice], speedTests: [SpeedTestResult], y: CGFloat) -> CGFloat {
        var cursor = drawSectionTitle("Summary", y: y)

        let onlineCount = devices.filter { $0.status == .online }.count
        let avgDownload: String
        if speedTests.isEmpty {
            avgDownload = "—"
        } else {
            let avg = speedTests.map(\.downloadSpeed).reduce(0, +) / Double(speedTests.count)
            avgDownload = String(format: "%.1f Mbps", avg)
        }

        let pairs: [(String, String)] = [
            ("Total Devices", "\(devices.count)"),
            ("Online", "\(onlineCount)"),
            ("Speed Tests", "\(speedTests.count)"),
            ("Avg Download", avgDownload)
        ]
        for (label, value) in pairs {
            cursor = drawKV(label: label, value: value, y: cursor)
        }
        return cursor + sectionGap
    }

    // MARK: - Devices Section

    private static func drawDevices(devices: [LocalDevice], ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = pageBreakIfNeeded(y: y, ctx: ctx)
        cursor = drawSectionTitle("Discovered Devices (\(devices.count))", y: cursor)
        cursor = drawRow(cols: ["IP Address", "Hostname", "Type", "Status"], y: cursor, header: true)

        for device in devices.prefix(35) {
            cursor = pageBreakIfNeeded(y: cursor, ctx: ctx)
            cursor = drawRow(cols: [
                device.ipAddress,
                device.hostname ?? "—",
                device.deviceType.displayName,
                device.status.statusType.label
            ], y: cursor, header: false)
        }
        return cursor + sectionGap
    }

    // MARK: - Tool Results Section

    private static func drawToolResults(toolResults: [ToolResult], ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = pageBreakIfNeeded(y: y, ctx: ctx)
        cursor = drawSectionTitle("Tool Results (\(min(toolResults.count, 25)))", y: cursor)
        cursor = drawRow(cols: ["Tool", "Target", "Result", "Date"], y: cursor, header: true)

        let fmt = makeDateFormatter()
        for result in toolResults.prefix(25) {
            cursor = pageBreakIfNeeded(y: cursor, ctx: ctx)
            cursor = drawRow(cols: [
                result.toolType.displayName,
                result.target,
                result.success ? "✓ \(result.summary)" : "✗ Failed",
                fmt.string(from: result.timestamp)
            ], y: cursor, header: false)
        }
        return cursor + sectionGap
    }

    // MARK: - Speed Test Section

    private static func drawSpeedTests(speedTests: [SpeedTestResult], ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = pageBreakIfNeeded(y: y, ctx: ctx)
        cursor = drawSectionTitle("Speed Test History (\(min(speedTests.count, 25)))", y: cursor)
        cursor = drawRow(cols: ["Date", "Download", "Upload", "Latency"], y: cursor, header: true)

        let fmt = makeDateFormatter()
        for test in speedTests.prefix(25) {
            cursor = pageBreakIfNeeded(y: cursor, ctx: ctx)
            cursor = drawRow(cols: [
                fmt.string(from: test.timestamp),
                String(format: "%.1f Mbps", test.downloadSpeed),
                String(format: "%.1f Mbps", test.uploadSpeed),
                String(format: "%.0f ms", test.latency)
            ], y: cursor, header: false)
        }
        return cursor + sectionGap
    }

    // MARK: - Drawing Primitives

    private static func drawSectionTitle(_ title: String, y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: headerBlue
        ]
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y + 17))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y + 17))
        headerBlue.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        return y + 24
    }

    private static func drawKV(label: String, value: String, y: CGFloat) -> CGFloat {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.black
        ]
        label.draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        value.draw(at: CGPoint(x: margin + 130, y: y), withAttributes: valueAttrs)
        return y + rowHeight
    }

    private static func drawRow(cols: [String], y: CGFloat, header: Bool) -> CGFloat {
        let colWidth = contentWidth / CGFloat(cols.count)
        let font: UIFont = header ? .boldSystemFont(ofSize: 9) : .systemFont(ofSize: 9)
        let textColor: UIColor = header ? .white : .black

        // Row background
        if header {
            tableBlue.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
        } else {
            let rowIndex = Int((y - margin) / rowHeight)
            if rowIndex % 2 == 0 {
                stripeFill.setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        for (i, col) in cols.enumerated() {
            let x = margin + CGFloat(i) * colWidth + 3
            let maxW = colWidth - 6
            let text = clipped(col, maxWidth: maxW, font: font)
            text.draw(at: CGPoint(x: x, y: y + 3), withAttributes: attrs)
        }
        return y + rowHeight
    }

    private static func clipped(_ string: String, maxWidth: CGFloat, font: UIFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var result = string
        while !result.isEmpty, (result as NSString).size(withAttributes: attrs).width > maxWidth {
            result = String(result.dropLast())
        }
        if result.count < string.count { result += "…" }
        return result
    }

    private static func pageBreakIfNeeded(y: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        if y > pageHeight - 60 {
            ctx.beginPage()
            return margin
        }
        return y
    }

    private static func makeDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }
}
