import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - SVGRenderer

/// Renders SVG data to PNG for use as heatmap base map.
/// Uses platform-native SVG rendering (NSImage on macOS, UIImage on iOS).
public enum SVGRenderer: Sendable {

    /// Render SVG data to PNG image data at the specified width.
    /// Height is calculated from the real-world aspect ratio.
    public static func renderToPNG(
        svgData: Data,
        width: Int,
        heightMeters: Double,
        widthMeters: Double
    ) -> Data {
        guard !svgData.isEmpty, widthMeters > 0 else {
            return Data()
        }

        let aspectRatio = heightMeters / widthMeters
        let height = Int(Double(width) * aspectRatio)

        #if canImport(AppKit)
        return renderWithAppKit(svgData: svgData, width: width, height: height)
        #elseif canImport(UIKit)
        return renderWithUIKit(svgData: svgData, width: width, height: height)
        #else
        return Data()
        #endif
    }

    #if canImport(AppKit)
    private static func renderWithAppKit(svgData: Data, width: Int, height: Int) -> Data {
        guard let svgImage = NSImage(data: svgData) else {
            return Data()
        }

        let targetSize = NSSize(width: width, height: height)
        let image = NSImage(size: targetSize)
        image.lockFocus()

        // White background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        // Draw SVG scaled to fit
        svgImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: svgImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return pngData
    }
    #endif

    #if canImport(UIKit)
    private static func renderWithUIKit(svgData: Data, width: Int, height: Int) -> Data {
        let targetSize = CGSize(width: width, height: height)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.pngData { context in
            // White background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            // Try to render SVG via UIImage
            if let svgImage = UIImage(data: svgData) {
                svgImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
    }

    /// Renders wall segments directly using Core Graphics (no SVG dependency).
    /// Used on iOS where UIImage cannot render SVG data.
    public static func renderWallsToPNG(
        walls: [WallSegment],
        roomLabels: [RoomLabel],
        widthMeters: Double,
        heightMeters: Double,
        renderWidth: Int = 2048
    ) -> Data {
        guard widthMeters > 0,
              heightMeters > 0,
              !(walls.isEmpty && roomLabels.isEmpty) else { return Data() }

        let aspectRatio = heightMeters / widthMeters
        let renderHeight = Int(Double(renderWidth) * aspectRatio)
        guard renderHeight > 0 else { return Data() }

        // Scale factor: pixels per meter
        let scaleX = Double(renderWidth) / widthMeters
        let scaleY = Double(renderHeight) / heightMeters

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: renderWidth,
            height: renderHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }

        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))

        // Draw walls — flip Y axis to match screen coordinates (origin at top-left)
        context.setStrokeColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        context.setLineCap(.round)

        let cgHeight = Double(renderHeight)

        for wall in walls {
            let x1 = wall.startX * scaleX
            let y1 = cgHeight - wall.startY * scaleY  // Flip Y
            let x2 = wall.endX * scaleX
            let y2 = cgHeight - wall.endY * scaleY  // Flip Y
            let strokeWidth = max(wall.thickness * min(scaleX, scaleY), 2.0)

            context.setLineWidth(strokeWidth)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
            context.strokePath()
        }

        // Draw room labels
        if !roomLabels.isEmpty {
            context.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
            let fontSize = CGFloat(widthMeters / 10.0 * scaleX) * 0.4

            for label in roomLabels {
                let x = label.normalizedX * Double(renderWidth)
                let y = cgHeight - label.normalizedY * cgHeight  // Flip Y

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: max(fontSize, 12)),
                    .foregroundColor: UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
                ]
                let textSize = (label.text as NSString).size(withAttributes: attrs)
                (label.text as NSString).draw(
                    at: CGPoint(x: x - textSize.width / 2, y: y - textSize.height / 2),
                    withAttributes: attrs
                )
            }
        }

        guard let cgImage = context.makeImage() else { return Data() }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData() ?? Data()
    }
    #endif
}

// MARK: - SVGFloorPlanGenerator

/// Generates SVG floor plan markup from wall segments and room labels.
/// Used to convert RoomPlan CapturedRoom data into a portable SVG document.
public enum SVGFloorPlanGenerator: Sendable {

    /// Generate an SVG document from wall segments and room labels.
    ///
    /// - Parameters:
    ///   - walls: Wall segments in meter coordinates (origin at top-left)
    ///   - roomLabels: Room labels with normalized coordinates (0.0-1.0)
    ///   - widthMeters: Total width of the floor plan in meters
    ///   - heightMeters: Total height of the floor plan in meters
    ///   - pixelsPerMeter: SVG rendering resolution (default: 50px/m)
    /// - Returns: SVG data as UTF-8 encoded Data
    public static func generateSVG(
        walls: [WallSegment],
        roomLabels: [RoomLabel],
        widthMeters: Double,
        heightMeters: Double,
        pixelsPerMeter: Double = 50.0
    ) -> Data {
        let svgWidth = widthMeters * pixelsPerMeter
        let svgHeight = heightMeters * pixelsPerMeter

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             viewBox="0 0 \(formatted(svgWidth)) \(formatted(svgHeight))"
             width="\(formatted(svgWidth))" height="\(formatted(svgHeight))">
          <rect width="100%" height="100%" fill="white"/>
          <g id="walls" stroke="#333333" stroke-linecap="round">\n
        """

        // Draw wall segments
        for wall in walls {
            let x1 = wall.startX * pixelsPerMeter
            let y1 = wall.startY * pixelsPerMeter
            let x2 = wall.endX * pixelsPerMeter
            let y2 = wall.endY * pixelsPerMeter
            let strokeWidth = max(wall.thickness * pixelsPerMeter, 2.0)

            svg += "    <line x1=\"\(formatted(x1))\" y1=\"\(formatted(y1))\" "
            svg += "x2=\"\(formatted(x2))\" y2=\"\(formatted(y2))\" "
            svg += "stroke-width=\"\(formatted(strokeWidth))\"/>\n"
        }

        svg += "  </g>\n"

        // Draw room labels
        if !roomLabels.isEmpty {
            svg += "  <g id=\"labels\" font-family=\"Helvetica, Arial, sans-serif\" "
            svg += "font-size=\"\(formatted(pixelsPerMeter * 0.4))\" "
            svg += "fill=\"#666666\" text-anchor=\"middle\">\n"

            for label in roomLabels {
                let x = label.normalizedX * svgWidth
                let y = label.normalizedY * svgHeight
                let escapedText = label.text
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                svg += "    <text x=\"\(formatted(x))\" y=\"\(formatted(y))\">"
                svg += "\(escapedText)</text>\n"
            }

            svg += "  </g>\n"
        }

        svg += "</svg>\n"

        return Data(svg.utf8)
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
