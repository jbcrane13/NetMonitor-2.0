import Foundation
import SwiftUI
import AppKit
import NetMonitorCore

@MainActor
@Observable
final class HeatmapSurveyViewModel {
    // MARK: - Published State
    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var selectedVisualization: HeatmapVisualization = .signalStrength
    var measurementMode: MeasurementMode = .passive
    var isMeasuring: Bool = false
    var showImportSheet: Bool = false
    var currentRSSI: Int = -100
    var currentSSID: String?

    // MARK: - Calibration State
    var isCalibrating: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var calibrationDistance: Double = 5.0 // meters
    var showCalibrationSheet: Bool = false

    // MARK: - Services
    private var wifiEngine: WiFiMeasurementEngine?
    private var renderer: HeatmapRenderer
    private let wifiService = MacWiFiInfoService()
    private var rssiTimer: Timer?

    // MARK: - Measurement Mode
    enum MeasurementMode: String, CaseIterable {
        case passive  // RSSI, SNR only
        case active   // + speed test, latency
    }

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    // MARK: - Live RSSI Updates

    func startLiveRSSITimer() {
        guard rssiTimer == nil else { return }
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.updateLiveRSSI()
            }
        }
    }

    func stopLiveRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    func onAppear() {
        startLiveRSSITimer()
    }

    func onDisappear() {
        stopLiveRSSITimer()
    }

    private func updateLiveRSSI() async {
        let wifiInfo = await wifiService.fetchCurrentWiFi()
        currentRSSI = wifiInfo?.signalDBm ?? -100
        currentSSID = wifiInfo?.ssid
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        calibrationPoints = []
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationPoints = []
    }

    func addCalibrationPoint(at normalizedPoint: CGPoint) {
        guard calibrationPoints.count < 2 else { return }

        let point = CalibrationPoint(
            pixelX: Double(normalizedPoint.x),
            pixelY: Double(normalizedPoint.y)
        )
        calibrationPoints.append(point)

        if calibrationPoints.count == 2 {
            showCalibrationSheet = true
        }
    }

    func completeCalibration(withDistance distance: Double) {
        guard calibrationPoints.count == 2,
              var project = surveyProject else { return }

        let metersPerPixel = CalibrationPoint.metersPerPixel(
            pointA: calibrationPoints[0],
            pointB: calibrationPoints[1],
            knownDistanceMeters: distance
        )

        let floorPlan = FloorPlan(
            id: project.floorPlan.id,
            imageData: project.floorPlan.imageData,
            widthMeters: Double(project.floorPlan.pixelWidth) * metersPerPixel,
            heightMeters: Double(project.floorPlan.pixelHeight) * metersPerPixel,
            pixelWidth: project.floorPlan.pixelWidth,
            pixelHeight: project.floorPlan.pixelHeight,
            origin: project.floorPlan.origin,
            calibrationPoints: calibrationPoints,
            walls: project.floorPlan.walls
        )

        project.floorPlan = floorPlan
        surveyProject = project
        isCalibrating = false
        calibrationPoints = []
        showCalibrationSheet = false
    }

    private func setupEngine() {
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(from url: URL) throws {
        let imageData = try Data(contentsOf: url)
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,  // Default, user can calibrate
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: url.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
        measurementPoints = []
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard let project = surveyProject, !isMeasuring else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        saveUndoState()

        let point: MeasurementPoint
        if measurementMode == .active {
            point = await wifiEngine?.takeActiveMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        } else {
            point = await wifiEngine?.takeMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        }

        measurementPoints.append(point)
    }

    // MARK: - Heatmap Rendering

    func renderHeatmap() -> CGImage? {
        renderer.render(points: measurementPoints, visualization: selectedVisualization)
    }

    // MARK: - Save/Load

    func saveProject(to url: URL) throws {
        guard var project = surveyProject else { return }
        project.measurementPoints = measurementPoints
        let manager = ProjectSaveLoadManager()
        try manager.save(project: project, to: url)
    }

    func loadProject(from url: URL) throws {
        let manager = ProjectSaveLoadManager()
        surveyProject = try manager.load(from: url)
        measurementPoints = surveyProject?.measurementPoints ?? []
    }

// MARK: - Undo Support

    private var undoStack: [[MeasurementPoint]] = []

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        undoStack.append(measurementPoints)
        measurementPoints = previousState
    }

    func canUndo() -> Bool {
        !undoStack.isEmpty
    }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        // Limit undo stack size
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    // MARK: - Point Deletion

    func deletePoint(at index: Int) {
        guard index >= 0 && index < measurementPoints.count else { return }
        saveUndoState()
        measurementPoints.remove(at: index)
    }

    func deletePoint(id: UUID) {
        if let index = measurementPoints.firstIndex(where: { $0.id == id }) {
            deletePoint(at: index)
        }
    }

    // MARK: - Clear

    func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
    }

    // MARK: - PDF Export

    func generatePDFReport() -> Data? {
        guard let project = surveyProject else { return nil }

        let pageWidth: CGFloat = 612 // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50

        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        // Page 1: Heatmap with legend
        pdfContext.beginPage(mediaBox: &mediaBox)
        var yPosition: CGFloat = margin

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        let title = "Wi-Fi Heatmap Report"
        title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
        yPosition += 40

        // Survey name
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.darkGray
        ]
        project.name.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttributes)
        yPosition += 30

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateString = "Generated: \(dateFormatter.string(from: Date()))"
        dateString.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttributes)
        yPosition += 40

        // Floor plan with heatmap
        let imageData = project.floorPlan.imageData
        if let nsImage = NSImage(data: imageData),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let maxWidth = pageWidth - (margin * 2)
            let maxHeight = pageHeight - yPosition - 200 // Leave room for legend

            let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
            var drawWidth = maxWidth
            var drawHeight = drawWidth / imageAspect

            if drawHeight > maxHeight {
                drawHeight = maxHeight
                drawWidth = drawHeight * imageAspect
            }

            let imageRect = CGRect(x: margin, y: yPosition, width: drawWidth, height: drawHeight)
            pdfContext.draw(cgImage, in: imageRect)

            // Draw heatmap overlay if available
            if let heatmapCG = renderHeatmap() {
                pdfContext.draw(heatmapCG, in: imageRect)
            }
            yPosition += drawHeight + 20
        }

        // Legend
        drawLegendPDF(context: pdfContext, at: CGPoint(x: margin, y: yPosition), width: pageWidth - (margin * 2))
        pdfContext.endPage()

        // Page 2: Summary Statistics
        pdfContext.beginPage(mediaBox: &mediaBox)
        yPosition = margin

        let sectionTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        "Summary Statistics".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionTitleAttributes)
        yPosition += 40

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]

        let stats = [
            "Total Measurement Points: \(measurementPoints.count)",
            "Survey Date: \(dateFormatter.string(from: project.createdAt))",
            "",
            "Signal Strength (RSSI):",
            "  - Average: \(String(format: "%.1f", project.averageRSSI ?? 0)) dBm",
            "  - Minimum: \(project.minRSSI ?? 0) dBm",
            "  - Maximum: \(project.maxRSSI ?? 0) dBm",
            "",
            "Floor Plan:",
            "  - Size: \(String(format: "%.1f", project.floorPlan.widthMeters))m x \(String(format: "%.1f", project.floorPlan.heightMeters))m",
            "  - Origin: \(project.floorPlan.origin.rawValue)"
        ]

        for line in stats {
            line.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 18
        }
        pdfContext.endPage()

        // Page 3: Per-point data
        pdfContext.beginPage(mediaBox: &mediaBox)
        yPosition = margin

        "Measurement Points Detail".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionTitleAttributes)
        yPosition += 40

        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]

        let headers = ["#", "RSSI", "SSID", "Channel", "X", "Y", "Time"]
        var xPosition = margin
        for header in headers {
            header.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: headerAttributes)
            xPosition += 70
        }
        yPosition += 15

        let pointAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black
        ]

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        for (index, point) in measurementPoints.prefix(30).enumerated() {
            xPosition = margin
            let row = [
                "\(index + 1)",
                "\(point.rssi) dBm",
                point.ssid ?? "-",
                point.channel.map(String.init) ?? "-",
                String(format: "%.2f", point.floorPlanX),
                String(format: "%.2f", point.floorPlanY),
                timeFormatter.string(from: point.timestamp)
            ]

            for cell in row {
                cell.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: pointAttributes)
                xPosition += 70
            }
            yPosition += 14

            if yPosition > pageHeight - margin {
                pdfContext.endPage()
                pdfContext.beginPage(mediaBox: &mediaBox)
                yPosition = margin
            }
        }
        pdfContext.endPage()

        return pdfData as Data
    }

    private func drawLegendPDF(context: CGContext, at point: CGPoint, width: CGFloat) {
        let legendY = point.y
        let boxSize: CGFloat = 20

        let legendLabelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]

        "Signal Strength Legend".draw(at: CGPoint(x: point.x, y: legendY), withAttributes: legendLabelAttributes)

        let colors: [(NSColor, String)] = [
            (.systemGreen, "-50 to 0 dBm (Excellent)"),
            (.systemYellow, "-70 to -50 dBm (Good)"),
            (.systemOrange, "-85 to -70 dBm (Fair)"),
            (.systemRed, "-100 to -85 dBm (Weak)")
        ]

        var xPos = point.x
        for (color, label) in colors {
            let rect = CGRect(x: xPos, y: legendY + 20, width: boxSize, height: boxSize)
            color.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.black.setStroke()
            NSBezierPath(rect: rect).stroke()

            label.draw(at: CGPoint(x: xPos + boxSize + 5, y: legendY + 20), withAttributes: legendLabelAttributes)
            xPos += 150
        }
    }
}

// MARK: - Errors

enum HeatmapError: Error, LocalizedError {
    case invalidImage
    case noFloorPlan
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image format"
        case .noFloorPlan: return "No floor plan loaded"
        case .saveFailed: return "Failed to save project"
        }
    }
}
