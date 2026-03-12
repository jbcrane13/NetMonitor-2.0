import AppKit
import Foundation
import NetMonitorCore
import SwiftUI

// MARK: - WiFiHeatmapViewModel

@MainActor
@Observable
final class WiFiHeatmapViewModel {

    // MARK: - Survey State

    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var isSurveying: Bool = false
    var isMeasuring: Bool = false
    var pendingMeasurementLocation: CGPoint?

    // MARK: - Live Signal

    private(set) var currentSignal: WiFiHeatmapService.SignalSnapshot?
    private(set) var nearbyAPs: [NearbyAP] = []

    // MARK: - Sidebar State

    enum SidebarMode: String, CaseIterable {
        case survey
        case analyze
    }

    var sidebarMode: SidebarMode = .survey
    var isSidebarCollapsed: Bool = false

    // MARK: - Visualization

    var selectedVisualization: HeatmapVisualization = .signalStrength
    var colorScheme: HeatmapColorScheme = .thermal
    var overlayOpacity: Double = 0.7
    var coverageThreshold: Double = -70 // dBm
    var isCoverageThresholdEnabled: Bool = false

    // MARK: - AP Filter

    var selectedAPFilter: String? // BSSID to filter by, nil = all

    var uniqueBSSIDs: [(bssid: String, ssid: String)] {
        let seen = Dictionary(grouping: measurementPoints, by: { $0.bssid ?? "unknown" })
        return seen.compactMap { (bssid, points) in
            guard bssid != "unknown" else { return nil }
            let ssid = points.first?.ssid ?? bssid
            return (bssid: bssid, ssid: ssid)
        }.sorted { $0.ssid < $1.ssid }
    }

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    var measurementMode: MeasurementMode = .passive

    // MARK: - Calibration

    var isCalibrating: Bool = false
    var isCalibrated: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var showCalibrationSheet: Bool = false

    // MARK: - Canvas

    var heatmapCGImage: CGImage?
    var showImportSheet: Bool = false
    var showPhotoPicker: Bool = false

    // MARK: - Heatmap State

    var isHeatmapGenerated: Bool = false

    // MARK: - Services

    private let heatmapService = WiFiHeatmapService()
    private var wifiEngine: WiFiMeasurementEngine?
    private var signalPollTask: Task<Void, Never>?
    private let renderer: HeatmapRenderer

    // MARK: - Undo

    private var undoStack: [[MeasurementPoint]] = []

    // MARK: - Init

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    private func setupEngine() {
        let wifiService = MacWiFiInfoService()
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Lifecycle

    func onAppear() {
        startSignalPolling()
    }

    func onDisappear() {
        stopSignalPolling()
    }

    // MARK: - Signal Polling

    func startSignalPolling() {
        guard signalPollTask == nil else { return }
        signalPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentSignal = self.heatmapService.currentSignal()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSignalPolling() {
        signalPollTask?.cancel()
        signalPollTask = nil
    }

    // MARK: - Nearby AP Scan

    func refreshNearbyAPs() {
        nearbyAPs = heatmapService.scanForNearbyAPs()
    }

    // MARK: - Survey Control

    func startSurvey() {
        guard surveyProject != nil, isCalibrated else { return }
        isSurveying = true
        sidebarMode = .survey
        isHeatmapGenerated = false
        heatmapCGImage = nil
    }

    func stopSurvey() {
        isSurveying = false
        generateHeatmap()
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard surveyProject != nil, !isMeasuring else { return }
        isMeasuring = true
        pendingMeasurementLocation = normalizedPoint
        defer {
            isMeasuring = false
            pendingMeasurementLocation = nil
        }

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

    // MARK: - Heatmap Generation

    func generateHeatmap() {
        let filteredPoints: [MeasurementPoint]
        if let bssid = selectedAPFilter {
            filteredPoints = measurementPoints.filter { $0.bssid == bssid }
        } else {
            filteredPoints = measurementPoints
        }

        guard !filteredPoints.isEmpty else {
            heatmapCGImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(
            opacity: overlayOpacity
        )
        let localRenderer = HeatmapRenderer(configuration: config)

        Task.detached { [selectedVisualization, colorScheme] in
            let image = localRenderer.render(
                points: filteredPoints,
                visualization: selectedVisualization,
                colorScheme: colorScheme
            )
            await MainActor.run { [weak self] in
                self?.heatmapCGImage = image
                self?.isHeatmapGenerated = true
            }
        }
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
            widthMeters: 10.0,
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
        heatmapCGImage = nil
        isHeatmapGenerated = false

        // Mandatory calibration after import
        startCalibration()
    }

    func importFloorPlan(imageData: Data, name: String) throws {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: name,
            floorPlan: floorPlan
        )
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false

        startCalibration()
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        isCalibrated = false
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

        project.floorPlan = FloorPlan(
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

        surveyProject = project
        isCalibrating = false
        isCalibrated = true
        calibrationPoints = []
        showCalibrationSheet = false
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurementPoints = previous
        if isHeatmapGenerated { generateHeatmap() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    // MARK: - Point Management

    func deletePoint(id: UUID) {
        saveUndoState()
        measurementPoints.removeAll { $0.id == id }
        if isHeatmapGenerated { generateHeatmap() }
    }

    func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Project Save/Load

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
        isCalibrated = surveyProject?.floorPlan.calibrationPoints?.isEmpty == false
        if !measurementPoints.isEmpty {
            generateHeatmap()
        }
    }

    // MARK: - Export

    func exportPNG(canvasSize: CGSize) -> Data? {
        guard let heatmapCGImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: heatmapCGImage)
        return rep.representation(using: .png, properties: [:])
    }

    func exportPDF() -> Data? {
        guard let project = surveyProject,
              let floorPlanImage = NSImage(data: project.floorPlan.imageData) else { return nil }

        let pageWidth: CGFloat = 612 // Letter
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

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        let title = (project.name + " — WiFi Heatmap Report") as NSString
        title.draw(at: CGPoint(x: margin, y: pageHeight - margin - 20), withAttributes: titleAttrs)

        // Subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let subtitle = "Generated \(dateFormatter.string(from: Date())) · \(selectedVisualization.displayName) · \(colorScheme.displayName) scheme" as NSString
        subtitle.draw(at: CGPoint(x: margin, y: pageHeight - margin - 38), withAttributes: subtitleAttrs)

        // Floor plan + heatmap overlay
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

        // Draw floor plan
        if let cgImage = floorPlanImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pdfContext.draw(cgImage, in: imageRect)
        }

        // Draw heatmap overlay
        if let heatmap = heatmapCGImage {
            pdfContext.saveGState()
            pdfContext.setAlpha(CGFloat(overlayOpacity))
            pdfContext.draw(heatmap, in: imageRect)
            pdfContext.restoreGState()
        }

        // Draw measurement dots
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

        // Summary stats below image
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

            // Header row
            for (header, width) in columns {
                (header as NSString).draw(at: CGPoint(x: colX, y: tableY), withAttributes: headerAttrs)
                colX += width
            }
            tableY -= 14

            // Data rows
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            for (i, point) in pts.enumerated() {
                if tableY < margin + 20 {
                    pdfContext.endPDFPage()
                    pdfContext.beginPDFPage(nil)
                    tableY = pageHeight - margin - 20
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
                    timeFormatter.string(from: point.timestamp)
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

    // MARK: - Computed

    var filteredPoints: [MeasurementPoint] {
        if let bssid = selectedAPFilter {
            return measurementPoints.filter { $0.bssid == bssid }
        }
        return measurementPoints
    }

    var averageRSSI: Double? {
        let pts = filteredPoints
        guard !pts.isEmpty else { return nil }
        return Double(pts.reduce(0) { $0 + $1.rssi }) / Double(pts.count)
    }

    var minRSSI: Int? { filteredPoints.map(\.rssi).min() }
    var maxRSSI: Int? { filteredPoints.map(\.rssi).max() }
}

// MARK: - HeatmapError

enum HeatmapError: Error, LocalizedError {
    case invalidImage
    case noFloorPlan
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Invalid image format"
        case .noFloorPlan: "No floor plan loaded"
        case .saveFailed: "Failed to save project"
        }
    }
}
