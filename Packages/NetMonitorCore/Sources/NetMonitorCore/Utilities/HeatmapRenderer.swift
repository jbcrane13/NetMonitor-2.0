import Foundation

// MARK: - HeatmapRenderer

/// Pure-computation engine for heatmap rendering. No SwiftUI dependency.
/// Views call these methods and use the results to drive Canvas drawing.
public enum HeatmapRenderer {

    // MARK: - RGB Helper

    public struct RGB: Sendable {
        public let r: Int
        public let g: Int
        public let b: Int
    }

    // MARK: - Color Mapping

    /// Map an RSSI value (dBm) to an RGB color using the given scheme.
    /// RSSI range: −100 (weakest, t=0) … −30 (strongest, t=1)
    public static func colorComponents(rssi: Int, scheme: HeatmapColorScheme) -> RGB {
        let t = Double(rssi - (-100)) / Double((-30) - (-100))
        let tc = max(0.0, min(1.0, t))
        return interpolate(t: tc, stops: scheme.colorStops)
    }

    private static func interpolate(t: Double, stops: [(t: Double, hex: String)]) -> RGB {
        guard stops.count >= 2 else {
            return hexToRGB(stops.first?.hex ?? "000000")
        }
        var lo = stops[0]
        var hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if t >= stops[i].t && t <= stops[i + 1].t {
                lo = stops[i]
                hi = stops[i + 1]
                break
            }
        }
        let range = hi.t - lo.t
        let localT = range > 0 ? (t - lo.t) / range : 0.0
        let loRGB = hexToRGB(lo.hex)
        let hiRGB = hexToRGB(hi.hex)
        return RGB(
            r: Int(Double(loRGB.r) + Double(hiRGB.r - loRGB.r) * localT),
            g: Int(Double(loRGB.g) + Double(hiRGB.g - loRGB.g) * localT),
            b: Int(Double(loRGB.b) + Double(hiRGB.b - loRGB.b) * localT)
        )
    }

    private static func hexToRGB(_ hex: String) -> RGB {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let val = UInt32(h, radix: 16) ?? 0
        return RGB(r: Int((val >> 16) & 0xff), g: Int((val >> 8) & 0xff), b: Int(val & 0xff))
    }

    // MARK: - IDW Grid

    /// Compute a `gridSize×gridSize` matrix of interpolated RSSI values using
    /// Inverse Distance Weighting (all points within `maxRadiusPt`, 1/d² weights).
    /// Returns `nil` for cells with no nearby points (dead zones).
    public static func idwGrid(
        points: [HeatmapDataPoint],
        gridSize: Int,
        canvasWidth: Double,
        canvasHeight: Double,
        maxRadiusPt: Double = 80
    ) -> [[Double?]] {
        guard !points.isEmpty else {
            return Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)
        }
        let cellW = canvasWidth / Double(gridSize)
        let cellH = canvasHeight / Double(gridSize)
        var grid: [[Double?]] = Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cx = (Double(col) + 0.5) * cellW
                let cy = (Double(row) + 0.5) * cellH

                // Gather nearby points
                var weighted = 0.0
                var totalWeight = 0.0
                for pt in points {
                    let px = pt.x * canvasWidth
                    let py = pt.y * canvasHeight
                    let dx = cx - px
                    let dy = cy - py
                    let dist = sqrt(dx * dx + dy * dy)
                    guard dist < maxRadiusPt else { continue }
                    let w = dist < 0.001 ? 1e9 : 1.0 / (dist * dist)
                    weighted += w * Double(pt.signalStrength)
                    totalWeight += w
                }
                if totalWeight > 0 {
                    grid[row][col] = weighted / totalWeight
                }
            }
        }
        return grid
    }

    // MARK: - Stats

    public struct SurveyStats: Sendable {
        public let count: Int
        public let averageDBm: Int?
        public let strongestDBm: Int?
        public let weakestDBm: Int?
        /// Estimated coverage in square units (nil when uncalibrated).
        public let coverageArea: Double?
        /// % of measurement points that are >= -50 dBm.
        public let strongCoveragePercent: Int?
        /// Count of IDW cells with RSSI < -75 dBm.
        public let deadZoneCount: Int
    }

    public static func computeStats(
        points: [HeatmapDataPoint],
        calibration: CalibrationScale?,
        unit: DistanceUnit
    ) -> SurveyStats {
        guard !points.isEmpty else {
            return SurveyStats(count: 0, averageDBm: nil, strongestDBm: nil,
                               weakestDBm: nil, coverageArea: nil,
                               strongCoveragePercent: nil, deadZoneCount: 0)
        }
        let rssiValues = points.map { $0.signalStrength }
        let avg = rssiValues.reduce(0, +) / rssiValues.count
        let strongest = rssiValues.max()!
        let weakest = rssiValues.min()!
        let strongCount = rssiValues.filter { $0 >= -50 }.count
        let strongPct = (strongCount * 100) / rssiValues.count
        return SurveyStats(
            count: points.count,
            averageDBm: avg,
            strongestDBm: strongest,
            weakestDBm: weakest,
            coverageArea: nil,    // requires canvas size; computed in View
            strongCoveragePercent: strongPct,
            deadZoneCount: 0      // computed from IDW grid in View
        )
    }

    // MARK: - Scale Bar

    public struct ScaleBarConfig: Sendable {
        public let pixels: Double
        public let labelValue: Int
        public let unit: DistanceUnit
    }

    private static let roundNumbers = [1, 2, 5, 10, 25, 50, 100]

    /// Pick the largest round-number label that fits within `maxPixels`.
    public static func scaleBar(
        pixelsPerUnit: Double,
        unit: DistanceUnit,
        maxPixels: Double = 120
    ) -> ScaleBarConfig {
        guard pixelsPerUnit > 0 else {
            return ScaleBarConfig(pixels: 0, labelValue: 0, unit: unit)
        }
        var best = ScaleBarConfig(pixels: pixelsPerUnit, labelValue: 1, unit: unit)
        for n in roundNumbers {
            let px = pixelsPerUnit * Double(n)
            if px <= maxPixels { best = ScaleBarConfig(pixels: px, labelValue: n, unit: unit) }
        }
        return best
    }
}
