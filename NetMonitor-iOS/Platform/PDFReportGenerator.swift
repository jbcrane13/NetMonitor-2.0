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

    /// The model-written summary that opens a report, and the app's key points it was
    /// written from (#453).
    public struct ExecutiveSummary: Equatable, Sendable {
        /// The generated paragraph.
        public let text: String
        /// The judgements the app computed, shown word for word above the paragraph.
        public let keyPoints: [String]
        /// Who wrote `text`: this device or the connected Mac (#457).
        public let source: InsightSource

        public init(text: String, keyPoints: [String], source: InsightSource = .device) {
            self.text = text
            self.keyPoints = keyPoints
            self.source = source
        }
    }

    /// Generates a full network PDF report from provided data arrays.
    /// - Parameters:
    ///   - presence: what each device's saved status means as of the report (#583). Without it no
    ///     network has a scan, so no device reads online.
    ///   - executiveSummary: when given, an Executive Summary page comes first;
    ///     without it the report has no such page.
    /// - Returns: PDF data, or nil if rendering fails.
    public static func generateNetworkReport(
        devices: [LocalDevice],
        toolResults: [ToolResult],
        speedTests: [SpeedTestResult],
        presence: PresenceSnapshot = PresenceSnapshot(lastScans: [:], now: Date()),
        executiveSummary: ExecutiveSummary? = nil
    ) -> Data? {
        // Past devices (unseen for a week, #583) are counted, not listed.
        let past = devices.filter { presence.isPast($0) }
        let devices = devices.filter { !presence.isPast($0) }
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { ctx in
            if let executiveSummary {
                ctx.beginPage()
                drawExecutiveSummary(executiveSummary, y: drawHeader())
                drawFooter()
            }
            ctx.beginPage()
            var y = drawHeader()
            y = drawSummary(devices: devices, pastCount: past.count, presence: presence, speedTests: speedTests, y: y)

            if !devices.isEmpty || !past.isEmpty {
                y = drawDevices(devices: devices, pastCount: past.count, presence: presence, ctx: ctx, y: y)
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

    // MARK: - Executive Summary Page

    private static func drawExecutiveSummary(_ summary: ExecutiveSummary, y: CGFloat) {
        var cursor = drawSectionTitle("Executive Summary", y: y)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        for point in summary.keyPoints {
            "•".draw(at: CGPoint(x: margin, y: cursor), withAttributes: bodyAttrs)
            cursor = drawWrapped(point, x: margin + 14, y: cursor, width: contentWidth - 14, attributes: bodyAttrs) + 4
        }
        if !summary.keyPoints.isEmpty {
            cursor += sectionGap - 4
        }

        let noteAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 8),
            .foregroundColor: UIColor.gray
        ]
        let note = "Written by \(summary.source.modelName) from the figures in this report"
        cursor = drawWrapped(note, x: margin, y: cursor, width: contentWidth, attributes: noteAttrs) + 4
        _ = drawWrapped(summary.text, x: margin, y: cursor, width: contentWidth, attributes: bodyAttrs)
    }

    /// Draws `text` wrapped to `width` and returns the y below it.
    private static func drawWrapped(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let size = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: options,
            attributes: attributes,
            context: nil
        ).size
        let height = ceil(size.height)
        (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: height), options: options, attributes: attributes, context: nil)
        return y + height
    }

    // MARK: - Summary Section

    private static func drawSummary(
        devices: [LocalDevice], pastCount: Int, presence: PresenceSnapshot, speedTests: [SpeedTestResult], y: CGFloat
    ) -> CGFloat {
        var cursor = drawSectionTitle("Summary", y: y)

        let onlineCount = devices.count { presence.freshness(of: $0).isOnline }
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
            ("Past Devices", "\(pastCount)"),
            ("Speed Tests", "\(speedTests.count)"),
            ("Avg Download", avgDownload)
        ]
        for (label, value) in pairs {
            cursor = drawKV(label: label, value: value, y: cursor)
        }
        return cursor + sectionGap
    }

    // MARK: - Devices Section

    private static func drawDevices(
        devices: [LocalDevice], pastCount: Int, presence: PresenceSnapshot, ctx: UIGraphicsPDFRendererContext, y: CGFloat
    ) -> CGFloat {
        var cursor = pageBreakIfNeeded(y: y, ctx: ctx)
        let rows = devices.sorted { $0.lastSeen > $1.lastSeen }.prefix(35)
        cursor = drawSectionTitle("Discovered Devices (\(countLabel(shown: rows.count, total: devices.count)))", y: cursor)
        cursor = drawNote(statusAsOf(devices, presence: presence), y: cursor)
        cursor = drawRow(cols: ["IP Address", "Name", "Type", "Status", "Last Seen"], y: cursor, header: true)

        for device in rows {
            cursor = pageBreakIfNeeded(y: cursor, ctx: ctx)
            cursor = drawRow(cols: [
                device.ipAddress,
                device.displayName,
                device.deviceType.displayName,
                presence.freshness(of: device).label,
                PresenceFreshness.relativeText(since: device.lastSeen, now: presence.now)
            ], y: cursor, header: false)
        }
        if pastCount > 0 {
            let days = Int(PresenceFreshness.pastDeviceAge / 86400)
            cursor = drawNote("\(pastCount) past \(pastCount == 1 ? "device" : "devices") (not seen for \(days) days) not listed.", y: cursor)
        }
        return cursor + sectionGap
    }

    /// "Status as of 14:05; latest scan at 14:02." Times only: the report's header has the date.
    static func statusAsOf(_ devices: [LocalDevice], presence: PresenceSnapshot) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        let scans = Set(devices.map(\.networkProfileID)).compactMap { presence.lastScan(for: $0) }
        let scan = scans.max().map { "latest scan at \($0.formatted(time))" } ?? "no scan recorded"
        return "Status as of \(presence.now.formatted(time)); \(scan)."
    }

    private static func drawNote(_ text: String, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.italicSystemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
        return drawWrapped(text, x: margin, y: y + 2, width: contentWidth, attributes: attributes) + 4
    }

    // MARK: - Tool Results Section

    private static func drawToolResults(toolResults: [ToolResult], ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = pageBreakIfNeeded(y: y, ctx: ctx)
        let rows = toolResults.sorted { $0.timestamp > $1.timestamp }.prefix(25)
        cursor = drawSectionTitle("Tool Results (\(countLabel(shown: rows.count, total: toolResults.count)))", y: cursor)
        cursor = drawRow(cols: ["Tool", "Target", "Result", "Date"], y: cursor, header: true)

        let fmt = makeDateFormatter()
        for result in rows {
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
        let rows = speedTests.sorted { $0.timestamp > $1.timestamp }.prefix(25)
        cursor = drawSectionTitle("Speed Test History (\(countLabel(shown: rows.count, total: speedTests.count)))", y: cursor)
        cursor = drawRow(cols: ["Date", "Download", "Upload", "Latency"], y: cursor, header: true)

        let fmt = makeDateFormatter()
        for test in rows {
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

    /// A table title's count: "25 of 36" when the table is capped, else the total.
    private static func countLabel(shown: Int, total: Int) -> String {
        shown < total ? "\(shown) of \(total)" : "\(total)"
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
        if result.count < string.count {
            result += "…"
        }
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
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
