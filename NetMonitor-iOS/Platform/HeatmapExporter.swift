import CoreGraphics
import Foundation
import NetMonitorCore
import UIKit

// MARK: - HeatmapExporter

/// Composites the floor-plan image, the heatmap overlay, and the measurement
/// dots into a single `UIImage` for share-sheet export.
///
/// Extracted from ``HeatmapSurveyViewModel`` as part of #197 Phase 3 so the VM
/// no longer mixes survey state with Core Graphics rendering.
struct HeatmapExporter {

    /// Renders the composite export image. Returns `nil` if either the floor
    /// plan or its image data is missing.
    func renderImage(
        floorPlanImage: UIImage?,
        heatmapImage: CGImage?,
        points: [MeasurementPoint],
        heatmapOpacity: Double,
        canvasSize: CGSize
    ) -> UIImage? {
        guard let floorImage = floorPlanImage else { return nil }

        let imageRenderer = UIGraphicsImageRenderer(size: canvasSize)
        return imageRenderer.image { ctx in
            // Floor plan base layer
            floorImage.draw(in: CGRect(origin: .zero, size: canvasSize))

            // Heatmap overlay
            if let heatmapCG = heatmapImage {
                let heatmapUI = UIImage(cgImage: heatmapCG)
                ctx.cgContext.setAlpha(heatmapOpacity)
                heatmapUI.draw(in: CGRect(origin: .zero, size: canvasSize))
                ctx.cgContext.setAlpha(1.0)
            }

            // Measurement dots with glow
            for point in points {
                let x = point.floorPlanX * canvasSize.width
                let y = point.floorPlanY * canvasSize.height
                let color = RSSIQuality(rssi: point.rssi).uiColor
                let dotRadius: CGFloat = 6

                let glowRect = CGRect(
                    x: x - dotRadius * 1.5,
                    y: y - dotRadius * 1.5,
                    width: dotRadius * 3,
                    height: dotRadius * 3
                )
                ctx.cgContext.setFillColor(color.withAlphaComponent(0.3).cgColor)
                ctx.cgContext.fillEllipse(in: glowRect)

                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                ctx.cgContext.setFillColor(color.withAlphaComponent(0.8).cgColor)
                ctx.cgContext.fillEllipse(in: dotRect)

                let highlightRect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
                ctx.cgContext.fillEllipse(in: highlightRect)
            }
        }
    }

    /// Writes the project to a temporary `.netmonsurvey` file suitable for
    /// share-sheet export. Returns `nil` if the write fails.
    func exportProjectFile(
        project: SurveyProject,
        fileManager: HeatmapFileManager
    ) -> URL? {
        let fileName = project.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).netmonsurvey")

        do {
            try fileManager.save(project: project, to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
