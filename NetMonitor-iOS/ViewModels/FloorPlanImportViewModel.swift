import CoreLocation
import Foundation
import NetMonitorCore
import os
import UIKit

// MARK: - CalibrationUnit

/// The distance unit used for scale calibration on iOS.
enum CalibrationUnit: String, CaseIterable, Identifiable, Sendable {
    case meters = "Meters"
    case feet = "Feet"

    var id: String { rawValue }

    /// Conversion factor to meters.
    var toMeters: Double {
        switch self {
        case .meters: 1.0
        case .feet: 0.3048
        }
    }
}

// MARK: - ImportSource

/// Source from which a floor plan can be imported.
enum ImportSource: Sendable {
    case photoLibrary
    case files
}

// MARK: - FloorPlanImportViewModel

/// ViewModel for the iOS floor plan import and calibration workflow.
/// Manages the full new-project flow: name entry → floor plan import → scale calibration → ready to survey.
@MainActor
@Observable
final class FloorPlanImportViewModel {

    // MARK: - Project Name State

    /// The user-entered project name.
    var projectName: String = ""

    // MARK: - Import State

    /// Whether the photo library picker is being shown.
    var showPhotoLibraryPicker = false

    /// Whether the document picker is being shown.
    var showDocumentPicker = false

    /// The imported floor plan UIImage, or nil if not yet imported.
    private(set) var floorPlanImage: UIImage?

    /// The raw import result with image data and dimensions.
    private(set) var importResult: FloorPlanImportResult?

    /// Whether a floor plan has been imported.
    var hasFloorPlan: Bool { floorPlanImage != nil }

    /// Whether the import is currently in progress.
    private(set) var isImporting = false

    /// Error message from a failed import.
    var errorMessage: String?

    // MARK: - Calibration State

    /// Whether the calibration sheet is being shown.
    var showCalibrationSheet = false

    /// First calibration marker position (normalized 0-1).
    var calibrationPoint1 = CGPoint(x: 0.25, y: 0.5)

    /// Second calibration marker position (normalized 0-1).
    var calibrationPoint2 = CGPoint(x: 0.75, y: 0.5)

    /// Real-world distance between the two calibration points (as string for text field).
    var calibrationDistance: String = ""

    /// Unit for the calibration distance.
    var calibrationUnit: CalibrationUnit = .meters

    /// Whether calibration has been completed.
    private(set) var isCalibrated = false

    /// Pixels per meter ratio computed after calibration.
    private(set) var pixelsPerMeter: Double = 0

    // MARK: - Scale Bar

    /// Human-readable scale bar label (e.g., "5 m" or "10 ft").
    private(set) var scaleBarLabel: String = ""

    /// Scale bar width as a fraction of the floor plan width (0-1).
    private(set) var scaleBarFraction: Double = 0

    // MARK: - Location Permission

    /// Whether location permission has been granted (needed for NEHotspotNetwork).
    private(set) var isLocationAuthorized = false

    /// The current CLLocationManager authorization status.
    private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether the location permission prompt should be shown.
    var showLocationPermissionPrompt = false

    // MARK: - Navigation

    /// Whether the project is ready to begin surveying.
    private(set) var isReadyToSurvey = false

    /// The created SurveyProject, set when the user finishes setup.
    private(set) var createdProject: SurveyProject?

    // MARK: - Dependencies

    private let wifiService: any WiFiInfoServiceProtocol

    // MARK: - Init

    init(wifiService: any WiFiInfoServiceProtocol = WiFiInfoService()) {
        self.wifiService = wifiService
        checkLocationPermission()
    }

    // MARK: - Import from Photo Library (PHPicker result data)

    /// Handles image data received from PHPickerViewController.
    func handlePhotoLibraryResult(_ data: Data?) {
        guard let data else {
            errorMessage = "No image data received from photo library."
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            let result = try FloorPlanImporter.importFloorPlan(from: data)
            applyImportResult(result)
        } catch {
            errorMessage = error.localizedDescription
            Logger.heatmap.error("Photo library import failed: \(error.localizedDescription)")
        }

        isImporting = false
    }

    // MARK: - Import from Document Picker (file URL)

    /// Handles a file URL selected via UIDocumentPickerViewController.
    func handleDocumentPickerResult(_ url: URL) {
        isImporting = true
        errorMessage = nil

        // Access security-scoped resource
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try FloorPlanImporter.importFloorPlan(from: url)
            applyImportResult(result)
        } catch {
            errorMessage = error.localizedDescription
            Logger.heatmap.error("Document picker import failed: \(error.localizedDescription)")
        }

        isImporting = false
    }

    // MARK: - Apply Import Result

    /// Applies a successful import result, creating the UIImage and storing data.
    private func applyImportResult(_ result: FloorPlanImportResult) {
        guard let image = UIImage(data: result.imageData) else {
            errorMessage = "Failed to create image from imported data."
            return
        }

        floorPlanImage = image
        importResult = result

        Logger.heatmap.debug("Floor plan loaded: \(result.pixelWidth)x\(result.pixelHeight)")
    }

    // MARK: - Calibration

    /// Applies the two-point scale calibration.
    func applyCalibration() {
        guard let result = importResult else { return }

        guard let distanceValue = Double(calibrationDistance), distanceValue > 0 else {
            errorMessage = "Please enter a valid distance greater than zero."
            return
        }

        let distanceInMeters = distanceValue * calibrationUnit.toMeters

        // Compute pixel distance between the two calibration points
        let dx = (calibrationPoint2.x - calibrationPoint1.x) * Double(result.pixelWidth)
        let dy = (calibrationPoint2.y - calibrationPoint1.y) * Double(result.pixelHeight)
        let pixelDistance = sqrt(dx * dx + dy * dy)

        guard pixelDistance > 0 else {
            errorMessage = "Please place the calibration markers at different positions."
            return
        }

        pixelsPerMeter = pixelDistance / distanceInMeters
        isCalibrated = true
        showCalibrationSheet = false

        computeScaleBar()

        Logger.heatmap.debug("Calibration applied: \(self.pixelsPerMeter, format: .fixed(precision: 1)) px/m")
    }

    /// Skips calibration; the survey will use pixel coordinates.
    func skipCalibration() {
        isCalibrated = false
        pixelsPerMeter = 0
        scaleBarLabel = ""
        scaleBarFraction = 0
        showCalibrationSheet = false
    }

    /// Resets calibration markers and opens the calibration sheet.
    func beginCalibration() {
        calibrationPoint1 = CGPoint(x: 0.25, y: 0.5)
        calibrationPoint2 = CGPoint(x: 0.75, y: 0.5)
        calibrationDistance = ""
        showCalibrationSheet = true
    }

    // MARK: - Scale Bar Computation

    /// Computes a human-readable scale bar for the current calibration.
    private func computeScaleBar() {
        guard let result = importResult, pixelsPerMeter > 0 else { return }

        // Target: scale bar between 10-30% of floor plan width
        let floorPlanWidthPx = Double(result.pixelWidth)
        let targetFraction = 0.2
        let targetWidthPx = floorPlanWidthPx * targetFraction
        let targetDistanceM = targetWidthPx / pixelsPerMeter

        // Round to a nice number
        let roundedDistance = niceRound(targetDistanceM)
        let barWidthPx = roundedDistance * pixelsPerMeter

        scaleBarFraction = barWidthPx / floorPlanWidthPx

        // Format label
        if calibrationUnit == .feet {
            let feetValue = roundedDistance / CalibrationUnit.feet.toMeters
            let roundedFeet = niceRound(feetValue)
            scaleBarLabel = "\(formatDistance(roundedFeet)) ft"
        } else {
            scaleBarLabel = "\(formatDistance(roundedDistance)) m"
        }
    }

    /// Rounds a value to a "nice" number for scale bar display.
    private func niceRound(_ value: Double) -> Double {
        let niceValues: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 20, 25, 30, 50, 100]
        return niceValues.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    /// Formats a distance value for display, removing trailing zeros.
    private func formatDistance(_ value: Double) -> String {
        if value == value.rounded(.towardZero) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Location Permission

    /// Checks the current location authorization status.
    func checkLocationPermission() {
        if let service = wifiService as? WiFiInfoService {
            isLocationAuthorized = service.isLocationAuthorized
            locationAuthorizationStatus = service.authorizationStatus
        }
    }

    /// Requests location permission for Wi-Fi scanning.
    func requestLocationPermission() {
        if let service = wifiService as? WiFiInfoService {
            service.requestLocationPermission()
        }
    }

    // MARK: - Create Project

    /// Creates the SurveyProject from the current state and marks it ready to survey.
    func createProject() {
        guard let result = importResult else { return }

        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Please enter a project name."
            return
        }

        var calibrationPoints: [CalibrationPoint]?
        var widthMeters: Double = 0
        var heightMeters: Double = 0

        if isCalibrated, pixelsPerMeter > 0 {
            calibrationPoints = [
                CalibrationPoint(
                    pixelX: calibrationPoint1.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint1.y * Double(result.pixelHeight),
                    realWorldX: 0,
                    realWorldY: 0
                ),
                CalibrationPoint(
                    pixelX: calibrationPoint2.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint2.y * Double(result.pixelHeight),
                    realWorldX: 0,
                    realWorldY: 0
                )
            ]
            widthMeters = Double(result.pixelWidth) / pixelsPerMeter
            heightMeters = Double(result.pixelHeight) / pixelsPerMeter
        }

        let floorPlan = FloorPlan(
            imageData: result.imageData,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            pixelWidth: result.pixelWidth,
            pixelHeight: result.pixelHeight,
            // swiftlint:disable:next force_unwrapping
            origin: result.sourceURL.map { .imported($0) } ?? .imported(URL(string: "photo://library")!),
            calibrationPoints: calibrationPoints
        )

        let project = SurveyProject(
            name: name,
            floorPlan: floorPlan,
            surveyMode: .blueprint
        )

        createdProject = project
        isReadyToSurvey = true

        Logger.heatmap.debug("Project created: \(name), calibrated: \(self.isCalibrated)")
    }
}
