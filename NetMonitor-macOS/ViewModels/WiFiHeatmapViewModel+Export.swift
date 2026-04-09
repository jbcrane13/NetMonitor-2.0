// swiftlint:disable function_body_length
import AppKit
import Foundation
import NetMonitorCore

// MARK: - WiFiHeatmapViewModel + Export

extension WiFiHeatmapViewModel {

    func exportPNG(canvasSize: CGSize) -> Data? {
        guard let heatmapCGImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: heatmapCGImage)
        return rep.representation(using: .png, properties: [:])
    }

    private static let pdfDateFormatter: DateFormatter = {
// swiftlint:disable:next identifier_name
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    private static let pdfTimeFormatter: DateFormatter = {
// swiftlint:disable:next identifier_name
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    // swiftlint:disable:next cyclomatic_complexity
    func exportPDF() -> Data? {
        guard let project = surveyProject,
              let floorPlanImage = NSImage(data: project.floorPlan.imageData) else { return nil }

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        // === Page 1: Heatmap ===
        pdfContext.beginPDFPage(nil)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        let title = (project.name + " — WiFi Heatmap Report") as NSString
        title.draw(at: CGPoint(x: margin, y: pageHeight - margin - 20), withAttributes: titleAttrs)

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let subtitle = "Generated \(WiFiHeatmapViewModel.pdfDateFormatter.string(from: Date())) · \(selectedVisualization.displayName) · \(colorScheme.displayName) scheme" as NSString
        subtitle.draw(at: CGPoint(x: margin, y: pageHeight - margin - 38), withAttributes: subtitleAttrs)

        let imageTop = pageHeight - margin - 50
        let imageAreaW = pageWidth - margin * 2
        let imageAreaH: CGFloat = 420
        let floorPlanAspect = floorPlanImage.size.width / floorPlanImage.size.height
        let fitW: CGFloat
        let fitH: CGFloat
        if floorPlanAspect > imageAreaW / imageAreaH {
            fitW = imageAreaW
            fitH = imageAreaW / floorPlanAspect
        } else {
            fitH = imageAreaH
            fitW = imageAreaH * floorPlanAspect
        }
        let imgX = margin + (imageAreaW - fitW) / 2
        let imgY = imageTop - fitH
        let imageRect = CGRect(x: imgX, y: imgY, width: fitW, height: fitH)

        if let cgImage = floorPlanImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pdfContext.draw(cgImage, in: imageRect)
        }

        if let heatmap = heatmapCGImage {
            pdfContext.saveGState()
            pdfContext.setAlpha(CGFloat(overlayOpacity))
            pdfContext.draw(heatmap, in: imageRect)
            pdfContext.restoreGState()
        }

        let pts = filteredPoints
        for point in pts {
            let x = imageRect.minX + point.floorPlanX * imageRect.width
            let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height
            let dotR: CGFloat = 3
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fillEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
            pdfContext.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            pdfContext.setLineWidth(0.5)
            pdfContext.strokeEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
        }

        let statsY = imgY - 30
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        let boldStatsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]

        ("Summary" as NSString).draw(at: CGPoint(x: margin, y: statsY), withAttributes: boldStatsAttrs)

        var lineY = statsY - 18
        let stats: [(String, String)] = [
            ("Measurement Points", "\(pts.count)"),
            ("Avg RSSI", averageRSSI.map { String(format: "%.1f dBm", $0) } ?? "—"),
            ("Min RSSI", minRSSI.map { "\($0) dBm" } ?? "—"),
            ("Max RSSI", maxRSSI.map { "\($0) dBm" } ?? "—"),
            ("Floor Plan", String(format: "%.1f × %.1f m", project.floorPlan.widthMeters, project.floorPlan.heightMeters)),
            ("Visualization", selectedVisualization.displayName),
        ]

        for (label, value) in stats {
            let line = "\(label): \(value)" as NSString
            line.draw(at: CGPoint(x: margin + 10, y: lineY), withAttributes: statsAttrs)
            lineY -= 16
        }

        pdfContext.endPDFPage()

        // === Page 2: Per-Point Data Table ===
        if !pts.isEmpty {
            pdfContext.beginPDFPage(nil)

            ("Measurement Points Detail" as NSString).draw(
                at: CGPoint(x: margin, y: pageHeight - margin - 20),
                withAttributes: titleAttrs
            )

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 9),
                .foregroundColor: NSColor.black
            ]
            let cellAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.black
            ]

            let columns: [(String, CGFloat)] = [
                ("#", 25), ("RSSI", 45), ("SNR", 40), ("SSID", 100),
                ("Ch", 30), ("Band", 50), ("Speed↓", 55), ("Speed↑", 55),
                ("Latency", 50), ("Time", 70)
            ]

            var tableY = pageHeight - margin - 50
            var colX = margin

            for (header, width) in columns {
                (header as NSString).draw(at: CGPoint(x: colX, y: tableY), withAttributes: headerAttrs)
                colX += width
            }
            tableY -= 14

            for (i, point) in pts.enumerated() {
                if tableY < margin + 20 {
                    pdfContext.endPDFPage()
                    pdfContext.beginPDFPage(nil)
                    tableY = pageHeight - margin - 20
                    colX = margin
                    for (header, width) in columns {
                        (header as NSString).draw(at: CGPoint(x: colX, y: tableY), withAttributes: headerAttrs)
                        colX += width
                    }
                    tableY -= 14
                }

                colX = margin
                let rowData: [String] = [
                    "\(i + 1)",
                    "\(point.rssi)",
                    point.snr.map { "\($0)" } ?? "—",
                    point.ssid ?? "—",
                    point.channel.map { "\($0)" } ?? "—",
                    point.band?.rawValue ?? "—",
                    point.downloadSpeed.map { String(format: "%.1f", $0) } ?? "—",
                    point.uploadSpeed.map { String(format: "%.1f", $0) } ?? "—",
                    point.latency.map { String(format: "%.0f", $0) } ?? "—",
                    WiFiHeatmapViewModel.pdfTimeFormatter.string(from: point.timestamp)
                ]

                for (j, cell) in rowData.enumerated() {
                    (cell as NSString).draw(at: CGPoint(x: colX, y: tableY), withAttributes: cellAttrs)
                    colX += columns[j].1
                }
                tableY -= 12
            }

            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return pdfData as Data
    }
}

// swiftlint:enable function_body_length
