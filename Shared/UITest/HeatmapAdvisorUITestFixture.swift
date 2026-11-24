#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import NetMonitorCore
import UniformTypeIdentifiers

/// The finished survey both apps' UI tests open to see the heatmap advisor (#455): 25 points on a
/// plain plan, strong everywhere but the north-east corner. Compiled into both app targets, Debug
/// builds only (project.yml), so it never ships in the Core library or a release.
enum HeatmapAdvisorUITestFixture {
    /// The seeded survey's name; iOS saves it as "<name>.netmonsurvey".
    static let projectName = "UITest Weak Corner"

    /// What the UI tests' stand-in model answers. It states the fixture's action and place and
    /// no number, so it passes `InsightSummarizer`'s checks and `HeatmapAdvisorRequest.accepts`.
    static let answer = "Try moving the access point toward the north-east corner, where the signal is weak."

    /// The fixture survey, on a light grey 400 × 300 plan.
    static func project() -> SurveyProject {
        let points = stride(from: 0.0, through: 1.0, by: 0.25).flatMap { y in
            stride(from: 0.0, through: 1.0, by: 0.25).map { x in
                MeasurementPoint(
                    floorPlanX: x,
                    floorPlanY: y,
                    rssi: x >= 0.75 && y <= 0.25 ? -84 : -52,
                    ssid: "UITest",
                    bssid: "AA:BB:CC:00:00:01"
                )
            }
        }
        let plan = FloorPlan(
            imageData: planImage(width: 400, height: 300),
            widthMeters: 12,
            heightMeters: 9,
            pixelWidth: 400,
            pixelHeight: 300,
            calibrationPoints: [CalibrationPoint(pixelX: 0, pixelY: 0), CalibrationPoint(pixelX: 400, pixelY: 0, realWorldX: 12)]
        )
        return SurveyProject(name: projectName, floorPlan: plan, measurementPoints: points)
    }

    /// A PNG of a plain grey plan with a darker outline.
    private static func planImage(width: Int, height: Int) -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(CGColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
        context.setLineWidth(6)
        context.stroke(CGRect(x: 3, y: 3, width: width - 6, height: height - 6))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : Data()
    }
}
#endif
