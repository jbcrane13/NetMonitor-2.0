import Foundation
import Testing
@testable import NetMonitorCore

@Suite("HeatmapRenderer")
struct HeatmapRendererTests {

    // MARK: - Color interpolation

    @Test("colorForRSSI at minimum returns first stop color")
    func colorAtMin() {
        let rgb = HeatmapRenderer.colorComponents(rssi: -100, scheme: .thermal)
        // t=0 → hex "000080" → r=0, g=0, b=128
        #expect(rgb.r == 0)
        #expect(rgb.g == 0)
        #expect(rgb.b == 128)
    }

    @Test("colorForRSSI at maximum returns last stop color")
    func colorAtMax() {
        let rgb = HeatmapRenderer.colorComponents(rssi: -30, scheme: .thermal)
        // t=1 → hex "ff0000" → r=255, g=0, b=0
        #expect(rgb.r == 255)
        #expect(rgb.g == 0)
        #expect(rgb.b == 0)
    }

    @Test("colorForRSSI clamps below -100")
    func colorBelowMin() {
        let rgb1 = HeatmapRenderer.colorComponents(rssi: -110, scheme: .thermal)
        let rgb2 = HeatmapRenderer.colorComponents(rssi: -100, scheme: .thermal)
        #expect(rgb1.r == rgb2.r && rgb1.g == rgb2.g && rgb1.b == rgb2.b)
    }

    // MARK: - IDW interpolation

    @Test("IDW grid with one point returns that point's RSSI at origin")
    func idwSinglePoint() {
        let points = [HeatmapDataPoint(x: 0.5, y: 0.5, signalStrength: -60, timestamp: Date())]
        let grid = HeatmapRenderer.idwGrid(points: points, gridSize: 4, canvasWidth: 100, canvasHeight: 100)
        // Centre cell (1,1) should be closest to (0.5,0.5) → rssi ≈ -60
        let centre = grid[1][1]
        #expect(centre != nil)
        #expect(abs(centre! - (-60)) < 5)
    }

    @Test("IDW grid cell far from all points returns nil when no points within 80pt")
    func idwFarCell() {
        // Point at top-left; query bottom-right at 200×200 canvas, far cell
        let points = [HeatmapDataPoint(x: 0.05, y: 0.05, signalStrength: -60, timestamp: Date())]
        let grid = HeatmapRenderer.idwGrid(points: points, gridSize: 4, canvasWidth: 200, canvasHeight: 200)
        // Bottom-right cell [3][3] should be ~190pt away (> 80pt threshold) → nil
        #expect(grid[3][3] == nil)
    }

    // MARK: - Stats

    @Test("stats with no points returns zeroed struct")
    func statsEmpty() {
        let stats = HeatmapRenderer.computeStats(points: [], calibration: nil, unit: .feet)
        #expect(stats.count == 0)
        #expect(stats.averageDBm == nil)
    }

    @Test("stats computes average correctly")
    func statsAverage() {
        let pts = [
            HeatmapDataPoint(x: 0, y: 0, signalStrength: -40, timestamp: Date()),
            HeatmapDataPoint(x: 1, y: 1, signalStrength: -60, timestamp: Date()),
        ]
        let stats = HeatmapRenderer.computeStats(points: pts, calibration: nil, unit: .feet)
        #expect(stats.averageDBm == -50)
        #expect(stats.strongestDBm == -40)
        #expect(stats.weakestDBm == -60)
    }

    // MARK: - Scale bar

    @Test("scaleBarLength picks a round number >= 50px")
    func scaleBar() {
        // 20px per foot, want a nice label
        let result = HeatmapRenderer.scaleBar(pixelsPerUnit: 20, unit: .feet)
        // Should pick 5 ft (= 100px) or 10 ft (= 200px) — both round numbers
        #expect(result.pixels >= 50)
        #expect([1, 2, 5, 10, 25, 50, 100].contains(result.labelValue))
    }
}
