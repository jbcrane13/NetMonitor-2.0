import Foundation
import NetMonitorCore
import os

// MARK: - HeatmapSurveyViewModel + Calibration

extension HeatmapSurveyViewModel {

    /// Begins the calibration workflow by presenting the calibration sheet.
    func startCalibration() {
        guard hasFloorPlan
        else { return }

        // Reset calibration markers to sensible defaults
        calibrationPoint1 = CGPoint(x: 0.25, y: 0.5)
        calibrationPoint2 = CGPoint(x: 0.75, y: 0.5)
        calibrationDistance = ""
        calibrationUnit = .meters
        isCalibrationSheetPresented = true
    }

    /// Applies the calibration using the current marker positions and distance.
    func applyCalibration() {
        guard let result = importResult,
              let distanceValue = Double(calibrationDistance),
              distanceValue > 0
        else {
            showError("Please enter a valid distance greater than zero")
            return
        }

        let distanceInMeters = distanceValue * calibrationUnit.toMeters

        // Compute pixel distance between the two calibration points
        let dx = (calibrationPoint2.x - calibrationPoint1.x) * Double(result.pixelWidth)
        let dy = (calibrationPoint2.y - calibrationPoint1.y) * Double(result.pixelHeight)
        let pixelDistance = sqrt(dx * dx + dy * dy)

        guard pixelDistance > 0
        else {
            showError("Calibration points must be at different locations")
            return
        }

        pixelsPerMeter = pixelDistance / distanceInMeters
        isCalibrated = true
        isCalibrationSheetPresented = false

        // Update floor plan dimensions in the project
        if var currentProject = project {
            let widthMeters = Double(result.pixelWidth) / pixelsPerMeter
            let heightMeters = Double(result.pixelHeight) / pixelsPerMeter
            currentProject.floorPlan.widthMeters = widthMeters
            currentProject.floorPlan.heightMeters = heightMeters
            currentProject.floorPlan.calibrationPoints = [
                CalibrationPoint(
                    pixelX: calibrationPoint1.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint1.y * Double(result.pixelHeight),
                    realWorldX: 0,
                    realWorldY: 0
                ),
                CalibrationPoint(
                    pixelX: calibrationPoint2.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint2.y * Double(result.pixelHeight),
                    realWorldX: distanceInMeters,
                    realWorldY: 0
                )
            ]
            project = currentProject
        }

        computeScaleBar()

        Logger.app.debug("Calibration complete: \(self.pixelsPerMeter, format: .fixed(precision: 2)) px/m")
    }

    /// Skips calibration and proceeds with pixel coordinates.
    func skipCalibration() {
        isCalibrationSheetPresented = false
        isCalibrated = false
        pixelsPerMeter = 0
        scaleBarLabel = ""
        scaleBarFraction = 0
    }

    /// Computes scale bar parameters for display.
    func computeScaleBar() {
        guard isCalibrated, pixelsPerMeter > 0, let result = importResult
        else { return }

        // Choose a round number for the scale bar distance
        let floorPlanWidthMeters = Double(result.pixelWidth) / pixelsPerMeter
        let targetBarFraction = 0.2 // aim for ~20% of image width
        let targetDistanceMeters = floorPlanWidthMeters * targetBarFraction

        // Round to a nice number
        let roundedDistance: Double
        if targetDistanceMeters >= 10 {
            roundedDistance = (targetDistanceMeters / 5).rounded() * 5
        } else if targetDistanceMeters >= 1 {
            roundedDistance = targetDistanceMeters.rounded()
        } else {
            roundedDistance = (targetDistanceMeters * 10).rounded() / 10
        }

        let barPixels = roundedDistance * pixelsPerMeter
        scaleBarFraction = barPixels / Double(result.pixelWidth)

        if calibrationUnit == .feet {
            let feetValue = roundedDistance / CalibrationUnit.feet.toMeters
            scaleBarLabel = "\(Int(feetValue)) ft"
        } else {
            if roundedDistance >= 1 {
                scaleBarLabel = "\(Int(roundedDistance)) m"
            } else {
                scaleBarLabel = String(format: "%.1f m", roundedDistance)
            }
        }
    }
}
