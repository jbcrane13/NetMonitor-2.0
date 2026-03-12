import AppKit
import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCanvasRepresentable

struct HeatmapCanvasRepresentable: NSViewRepresentable {
    let floorPlanImageData: Data?
    let measurementPoints: [MeasurementPoint]
    let calibrationPoints: [CalibrationPoint]
    let isCalibrating: Bool
    let isSurveying: Bool
    let isMeasuring: Bool
    let pendingMeasurementLocation: CGPoint?
    let heatmapCGImage: CGImage?
    let overlayOpacity: Double
    let coverageThreshold: Double?
    let onTap: (CGPoint) -> Void
    let onPointDelete: (UUID) -> Void

    func makeNSView(context: Context) -> HeatmapCanvasNS {
        let view = HeatmapCanvasNS()
        view.autoresizingMask = [.width, .height]
        view.onTap = onTap
        view.onPointDelete = onPointDelete
        return view
    }

    func updateNSView(_ nsView: HeatmapCanvasNS, context: Context) {
        nsView.floorPlanImageData = floorPlanImageData
        nsView.measurementPoints = measurementPoints
        nsView.calibrationPoints = calibrationPoints
        nsView.isCalibrating = isCalibrating
        nsView.isSurveying = isSurveying
        nsView.isMeasuring = isMeasuring
        nsView.pendingMeasurementLocation = pendingMeasurementLocation
        if isMeasuring { nsView.startPulseAnimation() } else { nsView.stopPulseAnimation() }
        nsView.heatmapCGImage = heatmapCGImage
        nsView.overlayOpacity = overlayOpacity
        nsView.coverageThreshold = coverageThreshold
        nsView.needsDisplay = true
    }
}

// MARK: - HeatmapCanvasNS

class HeatmapCanvasNS: NSView {

    var floorPlanImageData: Data?
    var measurementPoints: [MeasurementPoint] = []
    var calibrationPoints: [CalibrationPoint] = []
    var isCalibrating: Bool = false
    var isSurveying: Bool = false
    var isMeasuring: Bool = false
    var pendingMeasurementLocation: CGPoint?
    var heatmapCGImage: CGImage?
    var overlayOpacity: Double = 0.7
    var coverageThreshold: Double?
    var onTap: ((CGPoint) -> Void)?
    var onPointDelete: ((UUID) -> Void)?

    // Hover state
    private var hoveredPointID: UUID?
    private var mouseLocation: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateHoveredPoint()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredPointID = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        // Future: pan support
    }

    override func magnify(with event: NSEvent) {
        // Future: pinch zoom
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        handleTap(at: location)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Z handled at view level via .onCommand
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dark canvas background
        context.setFillColor(NSColor(white: 0.08, alpha: 1.0).cgColor)
        context.fill(bounds)

        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            drawEmptyState(context)
            return
        }

        let imageRect = calculateImageRect(imageSize: nsImage.size)

        // Floor plan
        context.draw(cgImage, in: imageRect)

        // Heatmap overlay
        if let heatmap = heatmapCGImage {
            context.saveGState()
            context.setAlpha(CGFloat(overlayOpacity))
            context.draw(heatmap, in: imageRect)
            context.restoreGState()
        }

        // Measurement points
        drawMeasurementPoints(context: context, imageRect: imageRect)

        // Pending measurement spinner
        if isMeasuring, let pending = pendingMeasurementLocation {
            drawPendingIndicator(context: context, at: pending, imageRect: imageRect)
        }

        // Calibration overlay
        if isCalibrating {
            drawCalibrationOverlay(context: context, imageRect: imageRect)
            drawCalibrationPoints(context: context, imageRect: imageRect)
        }

        // Color legend
        if heatmapCGImage != nil {
            drawColorLegend(context: context)
        }

        // Tooltip
        if let hoveredID = hoveredPointID,
           let point = measurementPoints.first(where: { $0.id == hoveredID }) {
            drawTooltip(context: context, point: point, imageRect: imageRect)
        }
    }

    // MARK: - Pending Measurement Indicator

    private var pulsePhase: CGFloat = 0
    private var pulseTimer: Timer?

    func startPulseAnimation() {
        guard pulseTimer == nil else { return }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase += 0.08
            if self.pulsePhase > .pi * 2 { self.pulsePhase -= .pi * 2 }
            self.needsDisplay = true
        }
    }

    func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
    }

    private func drawPendingIndicator(context: CGContext, at normalizedPoint: CGPoint, imageRect: CGRect) {
        let x = imageRect.minX + normalizedPoint.x * imageRect.width
        let y = imageRect.minY + (1 - normalizedPoint.y) * imageRect.height

        let pulseScale = 1.0 + 0.3 * sin(pulsePhase)
        let radius: CGFloat = 14 * pulseScale
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

        // Pulsing ring
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(2.5)
        context.strokeEllipse(in: rect)

        // Inner fill
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.15).cgColor)
        context.fillEllipse(in: rect)

        // Center dot
        let dotR: CGFloat = 3
        let dotRect = CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: dotRect)

        // "Measuring..." label
        let label = "Measuring..." as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.systemBlue
        ]
        let labelSize = label.size(withAttributes: attrs)
        let bgRect = CGRect(
            x: x - labelSize.width / 2 - 6,
            y: y + radius + 4,
            width: labelSize.width + 12,
            height: labelSize.height + 4
        )
        context.setFillColor(NSColor(white: 0.1, alpha: 0.85).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()
        label.draw(at: CGPoint(x: bgRect.minX + 6, y: bgRect.minY + 2), withAttributes: attrs)
    }

    // MARK: - Measurement Points

    private func drawMeasurementPoints(context: CGContext, imageRect: CGRect) {
        for point in measurementPoints {
            let x = imageRect.minX + point.floorPlanX * imageRect.width
            let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height

            let isHovered = point.id == hoveredPointID

            if isSurveying || heatmapCGImage == nil {
                // Halo mode: colored ring based on RSSI
                let haloRadius: CGFloat = isHovered ? 14 : 10
                let haloRect = CGRect(x: x - haloRadius, y: y - haloRadius,
                                      width: haloRadius * 2, height: haloRadius * 2)
                context.setFillColor(rssiColor(point.rssi).withAlphaComponent(0.3).cgColor)
                context.fillEllipse(in: haloRect)
                context.setStrokeColor(rssiColor(point.rssi).cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: haloRect)
            }

            // Center dot
            let dotRadius: CGFloat = isHovered ? 5 : 4
            let dotRect = CGRect(x: x - dotRadius, y: y - dotRadius,
                                 width: dotRadius * 2, height: dotRadius * 2)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dotRect)

            // Outline
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: dotRect)
        }
    }

    // MARK: - Calibration Overlay

    private func drawCalibrationOverlay(context: CGContext, imageRect: CGRect) {
        // Semi-transparent overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fill(imageRect)

        // Instruction banner
        let bannerH: CGFloat = 60
        let bannerRect = CGRect(
            x: imageRect.midX - 200,
            y: imageRect.midY - bannerH / 2,
            width: 400,
            height: bannerH
        )
        context.setFillColor(NSColor(white: 0.1, alpha: 0.9).cgColor)
        let bannerPath = CGPath(roundedRect: bannerRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.addPath(bannerPath)
        context.fillPath()

        let pointsNeeded = 2 - calibrationPoints.count
        let title: String
        let subtitle: String
        if pointsNeeded > 0 {
            title = "Calibrate Floor Plan Scale"
            subtitle = "Click \(pointsNeeded) point\(pointsNeeded == 1 ? "" : "s") with a known distance between them"
        } else {
            title = "Calibration Points Set"
            subtitle = "Enter the distance in the calibration panel"
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.lightGray
        ]

        let titleStr = title as NSString
        let subtitleStr = subtitle as NSString
        let titleSize = titleStr.size(withAttributes: titleAttrs)
        let subtitleSize = subtitleStr.size(withAttributes: subtitleAttrs)

        titleStr.draw(at: CGPoint(
            x: bannerRect.midX - titleSize.width / 2,
            y: bannerRect.midY - titleSize.height + 2
        ), withAttributes: titleAttrs)
        subtitleStr.draw(at: CGPoint(
            x: bannerRect.midX - subtitleSize.width / 2,
            y: bannerRect.midY + 4
        ), withAttributes: subtitleAttrs)
    }

    // MARK: - Calibration Points

    private func drawCalibrationPoints(context: CGContext, imageRect: CGRect) {
        for (index, point) in calibrationPoints.enumerated() {
            let x = imageRect.minX + point.pixelX * imageRect.width
            let y = imageRect.minY + (1 - point.pixelY) * imageRect.height
            let rect = CGRect(x: x - 12, y: y - 12, width: 24, height: 24)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: rect)

            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.3).cgColor)
            context.fillEllipse(in: rect)

            let label = "\(index + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2), withAttributes: attrs)
        }

        // Draw line between calibration points
        if calibrationPoints.count == 2 {
            let p1 = calibrationPoints[0]
            let p2 = calibrationPoints[1]
            let x1 = imageRect.minX + p1.pixelX * imageRect.width
            let y1 = imageRect.minY + (1 - p1.pixelY) * imageRect.height
            let x2 = imageRect.minX + p2.pixelX * imageRect.width
            let y2 = imageRect.minY + (1 - p2.pixelY) * imageRect.height

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: - Color Legend

    private func drawColorLegend(context: CGContext) {
        let legendW: CGFloat = 200
        let legendH: CGFloat = 16
        let legendX = (bounds.width - legendW) / 2
        let legendY: CGFloat = 12

        // Background pill
        let bgRect = CGRect(x: legendX - 40, y: legendY - 4, width: legendW + 80, height: legendH + 16)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        // Gradient bar
        let gradientRect = CGRect(x: legendX, y: legendY, width: legendW, height: legendH)
        let colors = [
            NSColor.systemBlue.cgColor,
            NSColor.systemCyan.cgColor,
            NSColor.systemGreen.cgColor,
            NSColor.systemYellow.cgColor,
            NSColor.systemRed.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.25, 0.5, 0.75, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: locations) {
            context.saveGState()
            context.clip(to: gradientRect)
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: gradientRect.minX, y: gradientRect.midY),
                                       end: CGPoint(x: gradientRect.maxX, y: gradientRect.midY),
                                       options: [])
            context.restoreGState()
        }

        // Labels
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.lightGray
        ]
        let leftLabel = "-90" as NSString
        let rightLabel = "-30 dBm" as NSString
        leftLabel.draw(at: CGPoint(x: legendX - 30, y: legendY), withAttributes: labelAttrs)
        rightLabel.draw(at: CGPoint(x: legendX + legendW + 4, y: legendY), withAttributes: labelAttrs)
    }

    // MARK: - Tooltip

    private func drawTooltip(context: CGContext, point: MeasurementPoint, imageRect: CGRect) {
        let x = imageRect.minX + point.floorPlanX * imageRect.width
        let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height

        let lines = buildTooltipLines(point)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: rssiColor(point.rssi)
        ]

        let lineHeight: CGFloat = 14
        let padding: CGFloat = 8
        let tooltipW: CGFloat = 160
        let tooltipH = CGFloat(lines.count + 1) * lineHeight + padding * 2

        var tooltipX = x + 16
        var tooltipY = y - tooltipH / 2
        // Keep on screen
        if tooltipX + tooltipW > bounds.maxX - 8 { tooltipX = x - tooltipW - 16 }
        if tooltipY < 8 { tooltipY = 8 }
        if tooltipY + tooltipH > bounds.maxY - 8 { tooltipY = bounds.maxY - tooltipH - 8 }

        let tooltipRect = CGRect(x: tooltipX, y: tooltipY, width: tooltipW, height: tooltipH)
        context.setFillColor(NSColor(white: 0.1, alpha: 0.95).cgColor)
        let path = CGPath(roundedRect: tooltipRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        context.addPath(path)
        context.strokePath()

        // Header line: RSSI + quality
        let header = "\(point.rssi) dBm · \(qualityLabel(point.rssi))" as NSString
        header.draw(at: CGPoint(x: tooltipX + padding, y: tooltipY + padding), withAttributes: boldAttrs)

        // Detail lines
        for (i, line) in lines.enumerated() {
            let lineStr = line as NSString
            lineStr.draw(at: CGPoint(
                x: tooltipX + padding,
                y: tooltipY + padding + CGFloat(i + 1) * lineHeight
            ), withAttributes: attrs)
        }
    }

    private func buildTooltipLines(_ point: MeasurementPoint) -> [String] {
        var lines: [String] = []
        if let snr = point.snr { lines.append("SNR: \(snr) dB") }
        if let ssid = point.ssid { lines.append("SSID: \(ssid)") }
        if let ch = point.channel, let band = point.band {
            lines.append("Ch \(ch) · \(band.rawValue)")
        }
        if let speed = point.linkSpeed { lines.append("Link: \(speed) Mbps") }
        if let dl = point.downloadSpeed { lines.append(String(format: "DL: %.1f Mbps", dl)) }
        if let ul = point.uploadSpeed { lines.append(String(format: "UL: %.1f Mbps", ul)) }
        if let lat = point.latency { lines.append(String(format: "Latency: %.1f ms", lat)) }

        lines.append(HeatmapCanvasNS.tooltipTimeFormatter.string(from: point.timestamp))

        return lines
    }

    // MARK: - Helpers

    private func calculateImageRect(imageSize: NSSize) -> CGRect {
        let aspectRatio = imageSize.width / imageSize.height
        let containerAspect = bounds.width / bounds.height

        let displayedWidth: CGFloat
        let displayedHeight: CGFloat
        if aspectRatio > containerAspect {
            displayedWidth = bounds.width
            displayedHeight = bounds.width / aspectRatio
        } else {
            displayedWidth = bounds.height * aspectRatio
            displayedHeight = bounds.height
        }

        let offsetX = (bounds.width - displayedWidth) / 2
        let offsetY = (bounds.height - displayedHeight) / 2
        return CGRect(x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight)
    }

    private func handleTap(at location: CGPoint) {
        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData) else { return }

        let imageRect = calculateImageRect(imageSize: nsImage.size)
        let tapX = (location.x - imageRect.minX) / imageRect.width
        let tapY = 1.0 - (location.y - imageRect.minY) / imageRect.height

        guard tapX >= 0, tapX <= 1, tapY >= 0, tapY <= 1 else { return }
        onTap?(CGPoint(x: tapX, y: tapY))
    }

    private func updateHoveredPoint() {
        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData) else {
            hoveredPointID = nil
            return
        }

        let imageRect = calculateImageRect(imageSize: nsImage.size)
        let hitRadius: CGFloat = 12

        hoveredPointID = measurementPoints.first { point in
            let x = imageRect.minX + point.floorPlanX * imageRect.width
            let y = imageRect.minY + (1 - point.floorPlanY) * imageRect.height
            let dx = mouseLocation.x - x
            let dy = mouseLocation.y - y
            return (dx * dx + dy * dy).squareRoot() < hitRadius
        }?.id
    }

    private func rssiColor(_ rssi: Int) -> NSColor {
        switch rssi {
        case -50...0: .systemGreen
        case -60 ..< -50: .systemYellow
        case -70 ..< -60: .systemOrange
        default: .systemRed
        }
    }

    private func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "Excellent"
        case -60 ..< -50: "Good"
        case -70 ..< -60: "Fair"
        default: "Weak"
        }
    }

    private func drawEmptyState(_ context: CGContext) {
        let text = "Import a floor plan to begin" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.gray
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ), withAttributes: attrs)
    }
}
