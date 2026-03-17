import CoreGraphics
import Foundation

// MARK: - HeatmapRenderer

public struct HeatmapRenderer: Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable, Equatable {
        public var powerParameter: Double
        public var gridWidth: Int
        public var gridHeight: Int
        public var opacity: Double

        public init(
            powerParameter: Double = 2.0,
            gridWidth: Int = 200,
            gridHeight: Int = 200,
            opacity: Double = 0.7
        ) {
            self.powerParameter = powerParameter
            self.gridWidth = gridWidth
            self.gridHeight = gridHeight
            self.opacity = opacity
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - IDW Interpolation

    public func interpolateGrid(
        points: [MeasurementPoint],
        visualization: HeatmapVisualization,
        width: Int? = nil,
        height: Int? = nil
    ) -> [[Double]] {
        let gridW = width ?? configuration.gridWidth
        let gridH = height ?? configuration.gridHeight

        let validPoints: [(x: Double, y: Double, value: Double)] = points.compactMap { point in
            guard let value = visualization.extractValue(from: point) else { return nil }
            return (x: point.floorPlanX, y: point.floorPlanY, value: value)
        }

        guard !validPoints.isEmpty else {
            return Array(repeating: Array(repeating: 0, count: gridW), count: gridH)
        }

        let power = configuration.powerParameter
        var grid = Array(repeating: Array(repeating: 0.0, count: gridW), count: gridH)

        for row in 0 ..< gridH {
            let ny = Double(row) / max(Double(gridH - 1), 1)
            for col in 0 ..< gridW {
                let nx = Double(col) / max(Double(gridW - 1), 1)
                grid[row][col] = idwValue(
                    x: nx, y: ny,
                    points: validPoints,
                    power: power
                )
            }
        }

        return grid
    }

    // MARK: - Color Mapping

    public func colorForValue(
        _ value: Double,
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme = .thermal
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let range = visualization.valueRange
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        var normalized: Double
        if visualization.isHigherBetter {
            normalized = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        } else {
            normalized = 1.0 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        }

        // Apply a contrast-enhancing S-curve for signal-based visualizations
        // to spread the perceptually important mid-range across more colors.
        if visualization == .signalStrength || visualization == .signalToNoise {
            normalized = contrastCurve(normalized)
        }

        let alpha = UInt8(configuration.opacity * 255)

        switch colorScheme {
        case .thermal:
            return thermalGradient(t: normalized, alpha: alpha)
        case .stoplight:
            return stoplightGradient(t: normalized, alpha: alpha)
        case .plasma:
            return plasmaGradient(t: normalized, alpha: alpha)
        case .wifiman:
            // Green (strong signal, t≈1) → yellow → red (weak signal, t≈0)
            return wifimanGradient(t: normalized, alpha: alpha)
        }
    }

    // MARK: - Rendering

    public func render(
        points: [MeasurementPoint],
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme = .thermal
    ) -> CGImage? {
        let grid = interpolateGrid(points: points, visualization: visualization)
        let gridW = configuration.gridWidth
        let gridH = configuration.gridHeight

        guard gridW > 0, gridH > 0 else { return nil }

        // Pre-compute point positions for distance-based alpha falloff
        let pointPositions = points.compactMap { p -> (x: Double, y: Double)? in
            guard visualization.extractValue(from: p) != nil else { return nil }
            return (x: p.floorPlanX, y: p.floorPlanY)
        }
        // Falloff radius in normalized coordinates — pixels beyond this distance are transparent
        let falloffRadius = 0.15

        var pixelData = [UInt8](repeating: 0, count: gridW * gridH * 4)

        for row in 0 ..< gridH {
            let ny = Double(row) / max(Double(gridH - 1), 1)
            for col in 0 ..< gridW {
                let nx = Double(col) / max(Double(gridW - 1), 1)
                let value = grid[row][col]
                var color = colorForValue(value, visualization: visualization, colorScheme: colorScheme)

                // Compute distance to nearest measurement point
                let minDist = pointPositions.reduce(Double.greatestFiniteMagnitude) { best, pt in
                    let dx = nx - pt.x
                    let dy = ny - pt.y
                    return min(best, (dx * dx + dy * dy).squareRoot())
                }

                // Fade alpha based on distance from nearest point
                if minDist > falloffRadius {
                    color.a = 0
                } else if minDist > falloffRadius * 0.5 {
                    let fadeT = (minDist - falloffRadius * 0.5) / (falloffRadius * 0.5)
                    color.a = UInt8(Double(color.a) * (1.0 - fadeT))
                }

                let offset = (row * gridW + col) * 4
                pixelData[offset] = color.r
                pixelData[offset + 1] = color.g
                pixelData[offset + 2] = color.b
                pixelData[offset + 3] = color.a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: gridW,
            height: gridH,
            bitsPerComponent: 8,
            bytesPerRow: gridW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }

    // MARK: - Contrast Curve

    /// Smooth S-curve that steepens transitions in the 0.3-0.7 range so
    /// nearby signal values map to visually distinct colors.
    /// Keeps 0->0 and 1->1 but spreads the mid-range across more of the gradient.
    private func contrastCurve(_ t: Double) -> Double {
        // Logistic sigmoid centered at 0.5
        let k = 5.0  // steepness — higher = more contrast in the mid-range
        let raw = 1.0 / (1.0 + exp(-k * (t - 0.5)))
        // Normalize so f(0)=0 and f(1)=1
        let low = 1.0 / (1.0 + exp(-k * (0.0 - 0.5)))
        let high = 1.0 / (1.0 + exp(-k * (1.0 - 0.5)))
        return (raw - low) / (high - low)
    }

    // MARK: - Private IDW

    private func idwValue(
        x: Double,
        y: Double,
        points: [(x: Double, y: Double, value: Double)],
        power: Double
    ) -> Double {
        var weightedSum = 0.0
        var totalWeight = 0.0

        for point in points {
            let dx = x - point.x
            let dy = y - point.y
            let distSquared = dx * dx + dy * dy

            if distSquared < 1e-10 {
                return point.value
            }

            let dist = distSquared.squareRoot()
            let weight = 1.0 / pow(dist, power)
            weightedSum += weight * point.value
            totalWeight += weight
        }

        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }

    // MARK: - Gradient Functions

    /// Thermal: Blue → Cyan → Green → Yellow → Red
    /// Standard network heatmap gradient used by NetSpot and similar tools.
    private func thermalGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double

        if c < 0.25 {
            // Blue → Cyan
            let local = c / 0.25
            r = 0
            g = local
            b = 1.0
        } else if c < 0.5 {
            // Cyan → Green
            let local = (c - 0.25) / 0.25
            r = 0
            g = 1.0
            b = 1.0 - local
        } else if c < 0.75 {
            // Green → Yellow
            let local = (c - 0.5) / 0.25
            r = local
            g = 1.0
            b = 0
        } else {
            // Yellow → Red
            let local = (c - 0.75) / 0.25
            r = 1.0
            g = 1.0 - local
            b = 0
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }

    /// Stoplight: Red → Orange → Yellow → Green
    /// Intuitive traffic-light gradient.
    private func stoplightGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double = 0

        if c < 0.33 {
            // Red → Orange
            let local = c / 0.33
            r = 1.0
            g = 0.4 * local
        } else if c < 0.66 {
            // Orange → Yellow
            let local = (c - 0.33) / 0.33
            r = 1.0
            g = 0.4 + 0.6 * local
        } else {
            // Yellow → Green
            let local = (c - 0.66) / 0.34
            r = 1.0 - local
            g = 0.6 + 0.4 * local
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }

    /// Plasma: Indigo → Purple → Red → Orange → Yellow
    /// Scientific color map with high perceptual contrast.
    private func plasmaGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        let b: Double

        if c < 0.25 {
            // Dark indigo → Purple
            let local = c / 0.25
            r = 0.05 + 0.35 * local
            g = 0.01 + 0.01 * local
            b = 0.2 + 0.3 * local
        } else if c < 0.5 {
            // Purple → Red
            let local = (c - 0.25) / 0.25
            r = 0.4 + 0.55 * local
            g = 0.02 + 0.08 * local
            b = 0.5 - 0.45 * local
        } else if c < 0.75 {
            // Red → Orange
            let local = (c - 0.5) / 0.25
            r = 0.95 + 0.05 * local
            g = 0.1 + 0.4 * local
            b = 0.05 - 0.05 * local
        } else {
            // Orange → Yellow
            let local = (c - 0.75) / 0.25
            r = 1.0
            g = 0.5 + 0.5 * local
            b = local * 0.1
        }

        return (r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255), a: alpha)
    }

    /// WiFiman-style gradient: green (t=1, strong signal) → yellow → red (t=0, weak signal).
    private func wifimanGradient(t: Double, alpha: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = min(max(t, 0), 1)
        let r: Double
        let g: Double
        if c < 0.5 {
            // Red → Yellow (t: 0→0.5)
            r = 1.0
            g = c * 2.0
        } else {
            // Yellow → Green (t: 0.5→1.0)
            r = 1.0 - (c - 0.5) * 2.0
            g = 1.0
        }
        return (r: UInt8(r * 255), g: UInt8(g * 255), b: 0, a: alpha)
    }

    // MARK: - Static Convenience

    /// Renders a heatmap using a temporary renderer sized to the given floor plan dimensions.
    /// Grid resolution is clamped to the floor plan size for accurate pixel mapping.
    public static func render(
        points: [MeasurementPoint],
        floorPlanWidth: Int,
        floorPlanHeight: Int,
        visualization: HeatmapVisualization,
        colorScheme: HeatmapColorScheme = .thermal
    ) -> CGImage? {
        let config = Configuration(
            gridWidth: min(floorPlanWidth, 512),
            gridHeight: min(floorPlanHeight, 512)
        )
        return HeatmapRenderer(configuration: config).render(
            points: points,
            visualization: visualization,
            colorScheme: colorScheme
        )
    }
}
