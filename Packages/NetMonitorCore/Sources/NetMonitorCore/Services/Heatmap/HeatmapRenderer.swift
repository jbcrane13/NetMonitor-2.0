import CoreGraphics
import Foundation

// MARK: - HeatmapResolution

/// The grid resolution used for heatmap interpolation.
public struct HeatmapResolution: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int = 200, height: Int = 200) {
        self.width = width
        self.height = height
    }
}

// MARK: - HeatmapColorScheme

/// Selects which color gradient to apply to the heatmap.
/// - `standard`: Phase 1/2 green → yellow → red
/// - `wifiman`: Phase 3 WiFiman blue → cyan → green → yellow → orange → red
public enum HeatmapColorScheme: Sendable, Equatable {
    case standard
    case wifiman
}

// MARK: - HeatmapColor

/// A simple RGBA color representation used by the renderer.
public struct HeatmapColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

// MARK: - ScaleBarInfo

/// Information needed to draw a scale bar on the heatmap.
public struct ScaleBarInfo: Sendable, Equatable {
    public let lengthMeters: Double
    public let lengthPixels: Int
    public let label: String

    public init(lengthMeters: Double, lengthPixels: Int, label: String) {
        self.lengthMeters = lengthMeters
        self.lengthPixels = lengthPixels
        self.label = label
    }
}

// MARK: - HeatmapRenderer

/// Renders WiFi heatmap overlays using Inverse Distance Weighting (IDW) interpolation.
///
/// IDW with p=2.0 (Shepard's method) is used to interpolate measurement values
/// across a 2D grid, then maps values to colors based on the selected visualization
/// type and color scheme.
///
/// Usage:
/// ```swift
/// let image = HeatmapRenderer.render(
///     points: measurementPoints,
///     floorPlanWidth: 800,
///     floorPlanHeight: 600,
///     visualization: .signalStrength
/// )
/// ```
public enum HeatmapRenderer {

    // MARK: - IDW Power Parameter

    /// Inverse Distance Weighting power parameter (Shepard's method).
    private static let idwPower: Double = 2.0

    /// Threshold for "zero distance" — if a query point is closer than this
    /// to a measurement point, we return the exact measurement value.
    private static let zeroDistanceThreshold: Double = 1e-10

    // MARK: - Public API

    /// Renders a heatmap as a `CGImage`.
    ///
    /// - Parameters:
    ///   - points: The measurement points to interpolate. Must have at least 3.
    ///   - floorPlanWidth: Output image width in pixels.
    ///   - floorPlanHeight: Output image height in pixels.
    ///   - visualization: Which metric to visualize.
    ///   - resolution: Grid resolution for IDW computation (default 200×200).
    ///   - opacity: Alpha channel value for all pixels (default 0.7).
    ///   - colorScheme: Color gradient scheme to use (default `.standard`).
    /// - Returns: A `CGImage` with the heatmap overlay, or `nil` if fewer than 3 points.
    public static func render(
        points: [MeasurementPoint],
        floorPlanWidth: Int,
        floorPlanHeight: Int,
        visualization: HeatmapVisualization,
        resolution: HeatmapResolution = HeatmapResolution(),
        opacity: Double = 0.7,
        colorScheme: HeatmapColorScheme = .standard
    ) -> CGImage? {
        guard points.count >= 3 else { return nil }

        // Filter points that have valid values for this visualization
        let validPoints = points.filter { extractValue(from: $0, for: visualization) != nil }
        guard validPoints.count >= 3 else { return nil }

        let gridWidth = resolution.width
        let gridHeight = resolution.height

        let valueExtractor: (MeasurementPoint) -> Double = { point in
            extractValue(from: point, for: visualization) ?? 0
        }

        // Compute IDW grid
        var pixelData = [UInt8](repeating: 0, count: floorPlanWidth * floorPlanHeight * 4)
        let alphaValue = UInt8(min(max(opacity * 255.0, 0), 255))

        let scaleX = 1.0 / Double(gridWidth)
        let scaleY = 1.0 / Double(gridHeight)
        let outputScaleX = Double(floorPlanWidth) / Double(gridWidth)
        let outputScaleY = Double(floorPlanHeight) / Double(gridHeight)

        // Pre-compute point positions and values
        let pointData: [(x: Double, y: Double, value: Double)] = validPoints.map {
            ($0.floorPlanX, $0.floorPlanY, valueExtractor($0))
        }

        for gy in 0 ..< gridHeight {
            let normalizedY = (Double(gy) + 0.5) * scaleY
            for gx in 0 ..< gridWidth {
                let normalizedX = (Double(gx) + 0.5) * scaleX

                let value = interpolateIDWFromData(
                    atX: normalizedX,
                    y: normalizedY,
                    pointData: pointData
                )

                let color = colorForValue(value, visualization: visualization, colorScheme: colorScheme)

                // Map grid cell to output pixels
                let outXStart = Int(Double(gx) * outputScaleX)
                let outXEnd = min(Int(Double(gx + 1) * outputScaleX), floorPlanWidth)
                let outYStart = Int(Double(gy) * outputScaleY)
                let outYEnd = min(Int(Double(gy + 1) * outputScaleY), floorPlanHeight)

                let redByte = UInt8(color.red * 255.0)
                let greenByte = UInt8(color.green * 255.0)
                let blueByte = UInt8(color.blue * 255.0)

                for py in outYStart ..< outYEnd {
                    for px in outXStart ..< outXEnd {
                        let offset = (py * floorPlanWidth + px) * 4
                        pixelData[offset] = redByte
                        pixelData[offset + 1] = greenByte
                        pixelData[offset + 2] = blueByte
                        pixelData[offset + 3] = alphaValue
                    }
                }
            }
        }

        // Create CGImage from pixel data
        return createCGImage(
            from: pixelData,
            width: floorPlanWidth,
            height: floorPlanHeight
        )
    }

    // MARK: - IDW Interpolation

    /// Performs IDW interpolation at a given normalized position.
    ///
    /// - Parameters:
    ///   - atX: Normalized X position (0.0–1.0).
    ///   - y: Normalized Y position (0.0–1.0).
    ///   - points: The measurement points to interpolate from.
    ///   - valueExtractor: Closure to extract the numeric value from a measurement point.
    /// - Returns: The interpolated value.
    public static func interpolateIDW(
        atX x: Double,
        y: Double,
        points: [MeasurementPoint],
        valueExtractor: (MeasurementPoint) -> Double
    ) -> Double {
        let pointData = points.map { ($0.floorPlanX, $0.floorPlanY, valueExtractor($0)) }
        return interpolateIDWFromData(atX: x, y: y, pointData: pointData)
    }

    /// Internal IDW using pre-computed point data for performance.
    private static func interpolateIDWFromData(
        atX x: Double,
        y: Double,
        pointData: [(x: Double, y: Double, value: Double)]
    ) -> Double {
        var weightedSum = 0.0
        var weightTotal = 0.0

        for point in pointData {
            let dx = x - point.x
            let dy = y - point.y
            let distSquared = dx * dx + dy * dy

            // Zero distance — return exact value
            if distSquared < zeroDistanceThreshold {
                return point.value
            }

            // IDW weight: 1 / d^p where p = 2.0
            // Since p = 2.0, weight = 1 / distSquared (avoiding sqrt)
            let weight = 1.0 / distSquared

            weightedSum += weight * point.value
            weightTotal += weight
        }

        guard weightTotal > 0 else { return 0 }
        return weightedSum / weightTotal
    }

    // MARK: - Value Extraction

    /// Extracts the numeric value for a given visualization type from a measurement point.
    ///
    /// - Parameters:
    ///   - point: The measurement point.
    ///   - visualization: The visualization type.
    /// - Returns: The extracted value, or `nil` if the field is not populated.
    public static func extractValue(
        from point: MeasurementPoint,
        for visualization: HeatmapVisualization
    ) -> Double? {
        switch visualization {
        case .signalStrength:
            return Double(point.rssi)
        case .signalToNoise:
            return point.snr.map { Double($0) }
        case .downloadSpeed:
            return point.downloadSpeed
        case .uploadSpeed:
            return point.uploadSpeed
        case .latency:
            return point.latency
        }
    }

    // MARK: - Color Mapping

    /// Maps a numeric value to an RGB color based on visualization type and color scheme.
    ///
    /// - Parameters:
    ///   - value: The interpolated numeric value.
    ///   - visualization: The visualization type.
    ///   - colorScheme: The color scheme to use.
    /// - Returns: An RGB color.
    public static func colorForValue(
        _ value: Double,
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme
    ) -> HeatmapColor {
        switch colorScheme {
        case .standard:
            return standardColor(forValue: value, visualization: visualization)
        case .wifiman:
            return wifimanColor(forSignalStrength: value)
        }
    }

    // MARK: - Standard Color Scheme (Green → Yellow → Red)

    /// Phase 1/2 standard color: green (good) → yellow (fair) → red (poor).
    private static func standardColor(
        forValue value: Double,
        visualization: HeatmapVisualization
    ) -> HeatmapColor {
        let normalized = normalizeValue(value, for: visualization)
        return greenYellowRedGradient(ratio: normalized)
    }

    /// Normalizes a raw value to 0.0 (worst) – 1.0 (best) for the given visualization.
    private static func normalizeValue(
        _ value: Double,
        for visualization: HeatmapVisualization
    ) -> Double {
        switch visualization {
        case .signalStrength:
            // RSSI: -100 (worst) to -20 (best)
            // Green >= -50, Yellow -50 to -70, Red <= -70
            return clamp((value - -100.0) / ((-20.0) - -100.0), min: 0, max: 1)

        case .signalToNoise:
            // SNR: 0 (worst) to 50 (best)
            // Green > 25, Yellow 15-25, Red < 15
            return clamp(value / 50.0, min: 0, max: 1)

        case .downloadSpeed:
            // 0 (worst) to 200 Mbps (best)
            // Green > 100, Yellow 25-100, Red < 25
            return clamp(value / 200.0, min: 0, max: 1)

        case .uploadSpeed:
            // Same thresholds as download
            return clamp(value / 200.0, min: 0, max: 1)

        case .latency:
            // 0ms (best) to 100ms (worst) — inverted!
            // Green < 10, Yellow 10-50, Red > 50
            return clamp(1.0 - (value / 100.0), min: 0, max: 1)
        }
    }

    /// Green → Yellow → Red gradient.
    /// `ratio = 1.0` → green, `ratio = 0.0` → red, `ratio = 0.5` → yellow.
    private static func greenYellowRedGradient(ratio: Double) -> HeatmapColor {
        // ratio=0 → red (1,0,0), ratio=0.5 → yellow (1,1,0), ratio=1 → green (0,1,0)
        let red: Double
        let green: Double

        if ratio <= 0.5 {
            // Red to yellow: red stays 1, green goes 0→1
            red = 1.0
            green = ratio * 2.0
        } else {
            // Yellow to green: red goes 1→0, green stays 1
            red = (1.0 - ratio) * 2.0
            green = 1.0
        }

        return HeatmapColor(red: red, green: green, blue: 0.0)
    }

    // MARK: - WiFiman Color Scheme (Blue → Cyan → Green → Yellow → Orange → Red)

    /// Phase 3 WiFiman color scheme for signal strength.
    /// Blue (-30 to -50 dBm, excellent) → Cyan → Green (-50 to -60) →
    /// Yellow (-60 to -70) → Orange (-70 to -80) → Red (-80 to -90+, dead zone).
    private static func wifimanColor(forSignalStrength rssi: Double) -> HeatmapColor {
        // Normalize: -30 (best, ratio=1) to -90 (worst, ratio=0)
        let ratio = clamp((rssi - -90.0) / ((-30.0) - -90.0), min: 0, max: 1)

        // 6-color gradient: 0→red, 0.2→orange, 0.4→yellow, 0.6→green, 0.8→cyan, 1.0→blue
        if ratio <= 0.2 {
            // Red (1,0,0) → Orange (1,0.5,0)
            let segment = ratio / 0.2
            return HeatmapColor(red: 1.0, green: 0.5 * segment, blue: 0.0)
        } else if ratio <= 0.4 {
            // Orange (1,0.5,0) → Yellow (1,1,0)
            let segment = (ratio - 0.2) / 0.2
            return HeatmapColor(red: 1.0, green: 0.5 + 0.5 * segment, blue: 0.0)
        } else if ratio <= 0.6 {
            // Yellow (1,1,0) → Green (0,1,0)
            let segment = (ratio - 0.4) / 0.2
            return HeatmapColor(red: 1.0 - segment, green: 1.0, blue: 0.0)
        } else if ratio <= 0.8 {
            // Green (0,1,0) → Cyan (0,1,1)
            let segment = (ratio - 0.6) / 0.2
            return HeatmapColor(red: 0.0, green: 1.0, blue: segment)
        } else {
            // Cyan (0,1,1) → Blue (0,0,1)
            let segment = (ratio - 0.8) / 0.2
            return HeatmapColor(red: 0.0, green: 1.0 - segment, blue: 1.0)
        }
    }

    // MARK: - Scale Bar

    /// Computes scale bar information for the heatmap overlay.
    ///
    /// - Parameters:
    ///   - floorPlanWidthMeters: Real-world width in meters (0 if uncalibrated).
    ///   - floorPlanHeightMeters: Real-world height in meters (0 if uncalibrated).
    ///   - imageWidth: Image width in pixels.
    ///   - imageHeight: Image height in pixels.
    /// - Returns: Scale bar info, or `nil` if the floor plan is uncalibrated.
    public static func computeScaleBar(
        floorPlanWidthMeters: Double,
        floorPlanHeightMeters: Double,
        imageWidth: Int,
        imageHeight: Int
    ) -> ScaleBarInfo? {
        guard floorPlanWidthMeters > 0, imageWidth > 0 else { return nil }

        let pixelsPerMeter = Double(imageWidth) / floorPlanWidthMeters

        // Choose a "nice" scale bar length (1, 2, 5, 10, 20, 50 meters)
        let targetPixels = Double(imageWidth) * 0.2 // ~20% of image width
        let targetMeters = targetPixels / pixelsPerMeter

        let niceLength = niceRoundNumber(targetMeters)
        let barPixels = Int(niceLength * pixelsPerMeter)

        let label: String
        if niceLength >= 1.0 {
            if niceLength == floor(niceLength) {
                label = "\(Int(niceLength)) m"
            } else {
                label = String(format: "%.1f m", niceLength)
            }
        } else {
            label = String(format: "%.0f cm", niceLength * 100)
        }

        return ScaleBarInfo(
            lengthMeters: niceLength,
            lengthPixels: barPixels,
            label: label
        )
    }

    // MARK: - Private Helpers

    /// Clamps a value to the given range.
    private static func clamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
        Swift.min(Swift.max(value, minVal), maxVal)
    }

    /// Rounds a value to a "nice" number for scale bar labels (1, 2, 5, 10, 20, 50, ...).
    private static func niceRoundNumber(_ value: Double) -> Double {
        guard value > 0 else { return 1.0 }

        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude

        let nice: Double
        if normalized <= 1.5 {
            nice = 1.0
        } else if normalized <= 3.5 {
            nice = 2.0
        } else if normalized <= 7.5 {
            nice = 5.0
        } else {
            nice = 10.0
        }

        return nice * magnitude
    }

    /// Creates a CGImage from raw RGBA pixel data.
    private static func createCGImage(
        from pixelData: [UInt8],
        width: Int,
        height: Int
    ) -> CGImage? {
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(
            data: Data(pixelData) as CFData
        ) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
