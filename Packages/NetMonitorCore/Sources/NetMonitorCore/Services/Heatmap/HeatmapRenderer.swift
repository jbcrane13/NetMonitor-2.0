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
        visualization: HeatmapVisualization
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let range = visualization.valueRange
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let normalized: Double
        if visualization.isHigherBetter {
            normalized = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        } else {
            normalized = 1.0 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        }
        let alpha = UInt8(configuration.opacity * 255)
        return gradientColor(normalizedValue: normalized, alpha: alpha)
    }

    // MARK: - Rendering

    public func render(
        points: [MeasurementPoint],
        visualization: HeatmapVisualization
    ) -> CGImage? {
        let grid = interpolateGrid(points: points, visualization: visualization)
        let gridW = configuration.gridWidth
        let gridH = configuration.gridHeight

        guard gridW > 0, gridH > 0 else { return nil }

        var pixelData = [UInt8](repeating: 0, count: gridW * gridH * 4)

        for row in 0 ..< gridH {
            for col in 0 ..< gridW {
                let value = grid[row][col]
                let color = colorForValue(value, visualization: visualization)
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

    // MARK: - Private

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

    private func gradientColor(
        normalizedValue: Double,
        alpha: UInt8
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let clamped = min(max(normalizedValue, 0), 1)

        let red: Double
        let green: Double
        let blue = 0.0

        if clamped < 0.5 {
            let local = clamped / 0.5
            red = 1.0
            green = local
        } else {
            let local = (clamped - 0.5) / 0.5
            red = 1.0 - local
            green = 1.0
        }

        return (
            r: UInt8(red * 255),
            g: UInt8(green * 255),
            b: UInt8(blue * 255),
            a: alpha
        )
    }
}
