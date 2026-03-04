import AppKit
import CoreGraphics
import Foundation
import NetMonitorCore
import os

// MARK: - HeatmapPDFExporter

/// Generates a 3-page PDF report from a heatmap survey project.
///
/// **Page 1:** Floor plan with heatmap overlay and color legend.
/// **Page 2:** Summary statistics (point count, RSSI stats, coverage info).
/// **Page 3:** Per-point measurement data table.
///
/// Requires at least 3 measurement points to generate the heatmap page.
enum HeatmapPDFExporter {

    // MARK: - Constants

    /// Standard US Letter page size in points (8.5 × 11 inches).
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 50

    // MARK: - Public API

    /// Generates a PDF report for the given survey project.
    ///
    /// - Parameters:
    ///   - project: The survey project to export.
    ///   - floorPlanImage: The floor plan image to render on page 1.
    ///   - heatmapOverlay: Optional pre-rendered heatmap overlay CGImage.
    ///   - visualization: The visualization type used for the heatmap.
    /// - Returns: PDF data, or nil if generation fails.
    static func generatePDF(
        project: SurveyProject,
        floorPlanImage: NSImage,
        heatmapOverlay: CGImage?,
        visualization: HeatmapVisualization
    ) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData)
        else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        // Page 1: Heatmap with legend
        drawHeatmapPage(
            context: pdfContext,
            project: project,
            floorPlanImage: floorPlanImage,
            heatmapOverlay: heatmapOverlay,
            visualization: visualization,
            mediaBox: mediaBox
        )

        // Page 2: Summary statistics
        drawStatsPage(
            context: pdfContext,
            project: project,
            visualization: visualization,
            mediaBox: mediaBox
        )

        // Page 3: Per-point data
        drawDataPage(
            context: pdfContext,
            project: project,
            mediaBox: mediaBox
        )

        pdfContext.closePDF()

        Logger.app.debug("PDF export generated: \(pdfData.length) bytes, \(project.measurementPoints.count) points")

        return pdfData as Data
    }

    /// Presents an NSSavePanel and saves the PDF data to the chosen location.
    /// - Parameters:
    ///   - pdfData: The PDF data to save.
    ///   - projectName: The default file name (without extension).
    /// - Returns: `true` if the save succeeded.
    @MainActor
    static func saveWithPanel(pdfData: Data, projectName: String) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Heatmap Report"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\(projectName) Report.pdf"
        panel.allowedContentTypes = [.pdf]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return false }

        do {
            try pdfData.write(to: url)
            Logger.app.info("PDF report saved to \(url.lastPathComponent)")
            return true
        } catch {
            Logger.app.error("Failed to save PDF: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Page 1: Heatmap + Legend

    private static func drawHeatmapPage(
        context: CGContext,
        project: SurveyProject,
        floorPlanImage: NSImage,
        heatmapOverlay: CGImage?,
        visualization: HeatmapVisualization,
        mediaBox: CGRect
    ) {
        context.beginPDFPage(nil)

        let contentWidth = pageWidth - margin * 2
        let titleY = pageHeight - margin

        // Title
        drawText(
            context: context,
            text: "WiFi Heatmap Report — \(project.name)",
            x: margin,
            y: titleY - 20,
            fontSize: 18,
            bold: true
        )

        // Subtitle with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: Date())
        drawText(
            context: context,
            text: "Generated: \(dateStr) · \(visualizationName(visualization))",
            x: margin,
            y: titleY - 42,
            fontSize: 10,
            color: .gray
        )

        // Floor plan with heatmap overlay
        let imageAreaTop = titleY - 60
        let imageAreaHeight = imageAreaTop - margin - 100 // Leave room for legend
        let imageAreaWidth = contentWidth

        // Calculate aspect-fit dimensions
        guard let cgFloorPlan = floorPlanImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            context.endPDFPage()
            return
        }

        let imageAspect = CGFloat(cgFloorPlan.width) / CGFloat(cgFloorPlan.height)
        let areaAspect = imageAreaWidth / imageAreaHeight

        let drawWidth: CGFloat
        let drawHeight: CGFloat
        if imageAspect > areaAspect {
            drawWidth = imageAreaWidth
            drawHeight = imageAreaWidth / imageAspect
        } else {
            drawHeight = imageAreaHeight
            drawWidth = imageAreaHeight * imageAspect
        }

        let drawX = margin + (imageAreaWidth - drawWidth) / 2
        let drawY = imageAreaTop - drawHeight
        let imageRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)

        // Draw floor plan
        context.draw(cgFloorPlan, in: imageRect)

        // Draw heatmap overlay on top
        if let overlay = heatmapOverlay {
            context.draw(overlay, in: imageRect)
        }

        // Draw border around image
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1.0))
        context.setLineWidth(0.5)
        context.stroke(imageRect)

        // Color legend
        drawColorLegend(
            context: context,
            visualization: visualization,
            x: margin,
            y: drawY - 30,
            width: contentWidth
        )

        context.endPDFPage()
    }

    // MARK: - Color Legend

    private static func drawColorLegend(
        context: CGContext,
        visualization: HeatmapVisualization,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) {
        let labels = legendLabels(for: visualization)
        let colors = legendColors()

        drawText(
            context: context,
            text: "\(visualizationName(visualization)) Legend",
            x: x,
            y: y,
            fontSize: 10,
            bold: true
        )

        let barY = y - 20
        let barHeight: CGFloat = 14
        let barWidth = width * 0.6
        let barX = x

        // Draw gradient bar
        let gradientColors = colors.map { $0.cgColor } as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: gradientColors,
            locations: nil
        ) {
            context.saveGState()
            context.clip(to: CGRect(x: barX, y: barY, width: barWidth, height: barHeight))
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: barX, y: barY),
                end: CGPoint(x: barX + barWidth, y: barY),
                options: []
            )
            context.restoreGState()
        }

        // Draw border around bar
        context.setStrokeColor(CGColor(gray: 0.5, alpha: 1.0))
        context.setLineWidth(0.5)
        context.stroke(CGRect(x: barX, y: barY, width: barWidth, height: barHeight))

        // Draw labels
        let labelSpacing = barWidth / CGFloat(labels.count - 1)
        for (index, label) in labels.enumerated() {
            let labelX = barX + labelSpacing * CGFloat(index)
            drawText(
                context: context,
                text: label,
                x: labelX - 15,
                y: barY - 14,
                fontSize: 8,
                color: .gray
            )
        }
    }

    // MARK: - Page 2: Summary Statistics

    private static func drawStatsPage(
        context: CGContext,
        project: SurveyProject,
        visualization: HeatmapVisualization,
        mediaBox: CGRect
    ) {
        context.beginPDFPage(nil)

        let contentWidth = pageWidth - margin * 2
        var y = pageHeight - margin

        // Title
        drawText(context: context, text: "Survey Summary", x: margin, y: y - 20, fontSize: 18, bold: true)
        y -= 50

        // Project info
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let infoRows: [(String, String)] = [
            ("Project Name", project.name),
            ("Created", dateFormatter.string(from: project.createdAt)),
            ("Survey Mode", surveyModeName(project.surveyMode)),
            ("Total Points", "\(project.measurementPoints.count)"),
            ("Floor Plan", "\(project.floorPlan.pixelWidth) × \(project.floorPlan.pixelHeight) px"),
            ("Calibrated", project.floorPlan.widthMeters > 0 ? "Yes" : "No")
        ]

        if project.floorPlan.widthMeters > 0 {
            let area = project.floorPlan.widthMeters * project.floorPlan.heightMeters
            drawSection(context: context, title: "Project Information", rows: infoRows + [
                ("Floor Area", String(format: "%.1f × %.1f m (%.0f m²)",
                                      project.floorPlan.widthMeters,
                                      project.floorPlan.heightMeters,
                                      area))
            ], x: margin, y: &y, width: contentWidth)
        } else {
            drawSection(context: context, title: "Project Information", rows: infoRows, x: margin, y: &y, width: contentWidth)
        }

        y -= 20

        // RSSI statistics
        let points = project.measurementPoints
        if !points.isEmpty {
            let rssiValues = points.map(\.rssi)
            let minRSSI = rssiValues.min() ?? 0
            let maxRSSI = rssiValues.max() ?? 0
            let avgRSSI = Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)

            var rssiRows: [(String, String)] = [
                ("Minimum RSSI", "\(minRSSI) dBm"),
                ("Maximum RSSI", "\(maxRSSI) dBm"),
                ("Average RSSI", String(format: "%.1f dBm", avgRSSI))
            ]

            // Noise floor stats (if available)
            let noiseValues = points.compactMap(\.noiseFloor)
            if !noiseValues.isEmpty {
                let avgNoise = Double(noiseValues.reduce(0, +)) / Double(noiseValues.count)
                rssiRows.append(("Avg Noise Floor", String(format: "%.1f dBm", avgNoise)))
            }

            // SNR stats (if available)
            let snrValues = points.compactMap(\.snr)
            if !snrValues.isEmpty {
                let avgSNR = Double(snrValues.reduce(0, +)) / Double(snrValues.count)
                rssiRows.append(("Avg SNR", String(format: "%.1f dB", avgSNR)))
            }

            drawSection(context: context, title: "Signal Statistics", rows: rssiRows, x: margin, y: &y, width: contentWidth)
            y -= 20

            // Speed/latency stats (if available)
            let dlSpeeds = points.compactMap(\.downloadSpeed)
            let ulSpeeds = points.compactMap(\.uploadSpeed)
            let latencies = points.compactMap(\.latency)

            if !dlSpeeds.isEmpty || !latencies.isEmpty {
                var speedRows: [(String, String)] = []
                if !dlSpeeds.isEmpty {
                    let avgDL = dlSpeeds.reduce(0, +) / Double(dlSpeeds.count)
                    speedRows.append(("Avg Download", String(format: "%.1f Mbps", avgDL)))
                }
                if !ulSpeeds.isEmpty {
                    let avgUL = ulSpeeds.reduce(0, +) / Double(ulSpeeds.count)
                    speedRows.append(("Avg Upload", String(format: "%.1f Mbps", avgUL)))
                }
                if !latencies.isEmpty {
                    let avgLat = latencies.reduce(0, +) / Double(latencies.count)
                    speedRows.append(("Avg Latency", String(format: "%.1f ms", avgLat)))
                }
                drawSection(context: context, title: "Performance Statistics", rows: speedRows, x: margin, y: &y, width: contentWidth)
                y -= 20
            }

            // Coverage distribution
            let excellent = points.filter { $0.rssi >= -50 }.count
            let good = points.filter { $0.rssi >= -70 && $0.rssi < -50 }.count
            let poor = points.filter { $0.rssi < -70 }.count

            let distRows: [(String, String)] = [
                ("Excellent (≥ -50 dBm)", "\(excellent) points (\(percentage(excellent, of: points.count))%)"),
                ("Good (-70 to -50 dBm)", "\(good) points (\(percentage(good, of: points.count))%)"),
                ("Poor (< -70 dBm)", "\(poor) points (\(percentage(poor, of: points.count))%)")
            ]
            drawSection(context: context, title: "Signal Distribution", rows: distRows, x: margin, y: &y, width: contentWidth)
        }

        // Metadata
        if let meta = project.metadata {
            y -= 20
            var metaRows: [(String, String)] = []
            if let building = meta.buildingName { metaRows.append(("Building", building)) }
            if let floor = meta.floorNumber { metaRows.append(("Floor", "\(floor)")) }
            if let notes = meta.notes { metaRows.append(("Notes", notes)) }
            if !metaRows.isEmpty {
                drawSection(context: context, title: "Location Information", rows: metaRows, x: margin, y: &y, width: contentWidth)
            }
        }

        // Footer
        drawPageFooter(context: context, pageNumber: 2, projectName: project.name)

        context.endPDFPage()
    }

    // MARK: - Page 3: Per-Point Data

    private static func drawDataPage(
        context: CGContext,
        project: SurveyProject,
        mediaBox: CGRect
    ) {
        context.beginPDFPage(nil)

        let contentWidth = pageWidth - margin * 2
        var y = pageHeight - margin

        // Title
        drawText(context: context, text: "Measurement Data", x: margin, y: y - 20, fontSize: 18, bold: true)
        y -= 50

        // Table header
        let columns: [(String, CGFloat)] = [
            ("#", 25),
            ("Time", 65),
            ("RSSI", 45),
            ("SSID", 90),
            ("Ch", 30),
            ("Band", 45),
            ("DL", 50),
            ("UL", 50),
            ("Lat", 40),
            ("X", 35),
            ("Y", 35)
        ]

        let rowHeight: CGFloat = 14
        let headerY = y

        // Draw header background
        context.setFillColor(CGColor(gray: 0.9, alpha: 1.0))
        context.fill(CGRect(x: margin, y: headerY - rowHeight + 2, width: contentWidth, height: rowHeight))

        var colX = margin
        for (title, width) in columns {
            drawText(context: context, text: title, x: colX + 2, y: headerY - rowHeight + 4, fontSize: 7, bold: true)
            colX += width
        }

        y = headerY - rowHeight - 2

        // Table rows
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        let points = project.measurementPoints
        var pageNumber = 3

        for (index, point) in points.enumerated() {
            // Check if we need a new page
            if y < margin + 30 {
                drawPageFooter(context: context, pageNumber: pageNumber, projectName: project.name)
                context.endPDFPage()
                context.beginPDFPage(nil)
                pageNumber += 1
                y = pageHeight - margin

                // Redraw header on new page
                drawText(context: context, text: "Measurement Data (continued)", x: margin, y: y - 20, fontSize: 14, bold: true)
                y -= 40

                context.setFillColor(CGColor(gray: 0.9, alpha: 1.0))
                context.fill(CGRect(x: margin, y: y - rowHeight + 2, width: contentWidth, height: rowHeight))

                colX = margin
                for (title, width) in columns {
                    drawText(context: context, text: title, x: colX + 2, y: y - rowHeight + 4, fontSize: 7, bold: true)
                    colX += width
                }
                y -= rowHeight + 2
            }

            // Alternate row background
            if index % 2 == 0 {
                context.setFillColor(CGColor(gray: 0.96, alpha: 1.0))
                context.fill(CGRect(x: margin, y: y - rowHeight + 2, width: contentWidth, height: rowHeight))
            }

            // Draw row data
            colX = margin
            let rowValues: [String] = [
                "\(index + 1)",
                dateFormatter.string(from: point.timestamp),
                "\(point.rssi)",
                point.ssid ?? "—",
                point.channel.map { "\($0)" } ?? "—",
                point.band.map { bandName($0) } ?? "—",
                point.downloadSpeed.map { String(format: "%.1f", $0) } ?? "—",
                point.uploadSpeed.map { String(format: "%.1f", $0) } ?? "—",
                point.latency.map { String(format: "%.1f", $0) } ?? "—",
                String(format: "%.2f", point.floorPlanX),
                String(format: "%.2f", point.floorPlanY)
            ]

            for (colIndex, value) in rowValues.enumerated() {
                let (_, width) = columns[colIndex]
                drawText(context: context, text: value, x: colX + 2, y: y - rowHeight + 4, fontSize: 7)
                colX += width
            }

            y -= rowHeight
        }

        // Footer
        drawPageFooter(context: context, pageNumber: pageNumber, projectName: project.name)

        context.endPDFPage()
    }

    // MARK: - Drawing Helpers

    private static func drawText(
        context: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: NSColor = .black
    ) {
        let font = bold
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        context.saveGState()
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawSection(
        context: CGContext,
        title: String,
        rows: [(String, String)],
        x: CGFloat,
        y: inout CGFloat,
        width: CGFloat
    ) {
        drawText(context: context, text: title, x: x, y: y, fontSize: 12, bold: true)
        y -= 20

        // Draw separator line
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: y + 14))
        context.addLine(to: CGPoint(x: x + width, y: y + 14))
        context.strokePath()

        for (label, value) in rows {
            drawText(context: context, text: label, x: x + 4, y: y, fontSize: 10, color: .darkGray)
            drawText(context: context, text: value, x: x + width * 0.45, y: y, fontSize: 10)
            y -= 16
        }
    }

    private static func drawPageFooter(
        context: CGContext,
        pageNumber: Int,
        projectName: String
    ) {
        let footerY: CGFloat = 30
        drawText(
            context: context,
            text: "\(projectName) — Page \(pageNumber)",
            x: margin,
            y: footerY,
            fontSize: 8,
            color: .gray
        )
        drawText(
            context: context,
            text: "NetMonitor WiFi Heatmap Report",
            x: pageWidth - margin - 150,
            y: footerY,
            fontSize: 8,
            color: .gray
        )
    }

    // MARK: - Label Helpers

    private static func visualizationName(_ viz: HeatmapVisualization) -> String {
        switch viz {
        case .signalStrength: "Signal Strength"
        case .signalToNoise: "Signal to Noise"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .latency: "Latency"
        }
    }

    private static func surveyModeName(_ mode: SurveyMode) -> String {
        switch mode {
        case .blueprint: "Blueprint Walk Survey"
        case .arAssisted: "AR-Assisted Survey"
        case .arContinuous: "AR Continuous Scan"
        }
    }

    private static func bandName(_ band: WiFiBand) -> String {
        switch band {
        case .band2_4GHz: "2.4G"
        case .band5GHz: "5G"
        case .band6GHz: "6G"
        }
    }

    private static func legendLabels(for visualization: HeatmapVisualization) -> [String] {
        switch visualization {
        case .signalStrength:
            return ["-90 dBm", "-70 dBm", "-50 dBm", "-30 dBm"]
        case .signalToNoise:
            return ["0 dB", "15 dB", "25 dB", "40 dB"]
        case .downloadSpeed:
            return ["0 Mbps", "25 Mbps", "100 Mbps", "200+ Mbps"]
        case .uploadSpeed:
            return ["0 Mbps", "25 Mbps", "100 Mbps", "200+ Mbps"]
        case .latency:
            return ["100+ ms", "50 ms", "10 ms", "0 ms"]
        }
    }

    private static func legendColors() -> [NSColor] {
        [
            NSColor.systemRed,
            NSColor.systemYellow,
            NSColor.systemGreen,
            NSColor(red: 0.0, green: 0.7, blue: 0.0, alpha: 1.0)
        ]
    }

    private static func percentage(_ count: Int, of total: Int) -> Int {
        guard total > 0
        else { return 0 }
        return Int(round(Double(count) / Double(total) * 100))
    }
}
