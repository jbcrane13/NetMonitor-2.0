import Foundation

/// What the heatmap advisor knows about a finished survey (#455). Pure: every figure is computed
/// here from the interpolated grid the renderer draws, and the advisor's model only words them.
/// Row 0 of the grid is the top of the plan, which counts as north.
public struct HeatmapSurveyStatistics: Sendable, Equatable {
    // MARK: - Thresholds

    /// Signal at or above this counts as good coverage.
    public static let goodRSSI = -67.0
    /// Signal at or above this, and below `goodRSSI`, counts as fair; below it is weak.
    public static let fairRSSI = -75.0
    /// Most weak regions reported, largest first.
    public static let maxWeakRegions = 3

    // MARK: - Types

    /// Shares of the surveyed area, in whole percent.
    public struct Coverage: Sendable, Equatable {
        public let good: Int
        public let fair: Int
        public let weak: Int

        public init(good: Int, fair: Int, weak: Int) {
            self.good = good
            self.fair = fair
            self.weak = weak
        }
    }

    /// A 3 × 3 position on the plan.
    public enum Compass: String, Sendable, Equatable, CaseIterable {
        case northWest = "north-west", north, northEast = "north-east"
        case west, centre, east
        case southWest = "south-west", south, southEast = "south-east"

        /// The position of normalized point (`x`, `y`), where (0, 0) is the top left.
        public init(x: Double, y: Double) {
            let col = min(Int(x * 3), 2)
            let row = min(Int(y * 3), 2)
            self = Self.allCases[max(row, 0) * 3 + max(col, 0)]
        }

        /// The place on a plan, such as "the north-east corner", "the north side" or "the centre".
        public var place: String {
            switch self {
            case .centre: "the centre"
            case .north, .south, .east, .west: "the \(rawValue) side"
            default: "the \(rawValue) corner"
            }
        }
    }

    /// Where a weak region is, in words the app writes.
    public enum Location: Sendable, Equatable {
        case compass(Compass)
        /// The labelled room nearest the region's centroid.
        case room(String)

        /// The location in a sentence, such as "the north-east corner" or "the Kitchen".
        public var phrase: String {
            switch self {
            case let .compass(compass): compass.place
            case let .room(name): "the \(name)"
            }
        }
    }

    /// Weak cells connected side by side or at a corner.
    public struct WeakRegion: Sendable, Equatable {
        /// Share of the surveyed area, in whole percent.
        public let areaPercent: Int
        /// Weakest signal in the region, in whole dBm.
        public let worstRSSI: Int
        /// Average signal in the region, in whole dBm.
        public let meanRSSI: Int
        public let location: Location
    }

    /// How often one access point was the strongest, the one a measurement was taken from.
    public struct AccessPointShare: Sendable, Equatable {
        /// The device's display name, or "access point ending :AB".
        public let name: String
        /// Share of the points that carry a BSSID, in whole percent.
        public let pointPercent: Int

        public init(name: String, pointPercent: Int) {
            self.name = name
            self.pointPercent = pointPercent
        }
    }

    // MARK: - Values

    public let pointCount: Int
    public let coverage: Coverage
    /// Up to `maxWeakRegions`, largest first.
    public let weakRegions: [WeakRegion]
    /// The direction signal falls off in, from the strongest cell toward the weakest; nil when
    /// the grid is even.
    public let falloff: Compass?
    /// Largest share first; empty when no point carries a BSSID.
    public let accessPoints: [AccessPointShare]

    // MARK: - Init

    /// Statistics of `grid`, signal in dBm per cell, nil outside the surveyed area. A weak region
    /// is named after the labelled room nearest its centroid when the plan has room labels.
    public init(
        grid: [[Double?]],
        pointCount: Int,
        roomLabels: [RoomLabel] = [],
        accessPoints: [AccessPointShare] = []
    ) {
        self.pointCount = pointCount
        self.accessPoints = accessPoints
        let cells = grid.flatMap { $0 }.compactMap { $0 }
        let total = max(cells.count, 1)
        let good = cells.count { $0 >= Self.goodRSSI }
        let weak = cells.count { $0 < Self.fairRSSI }
        coverage = Coverage(
            good: Self.percent(good, of: total),
            fair: Self.percent(cells.count - good - weak, of: total),
            weak: Self.percent(weak, of: total)
        )
        weakRegions = Self.weakRegions(in: grid, surveyedCells: total, roomLabels: roomLabels)
        falloff = Self.falloff(in: grid)
    }

    /// Statistics of a survey's `points`, on the grid `HeatmapRenderer` interpolates with
    /// `configuration`. Only cells the renderer draws, within `HeatmapRenderer.falloffRadius` of
    /// a point, are the surveyed area.
    /// - Parameter accessPointNames: device display names by normalized MAC (`accessPointNames(_:)`).
    public init(
        points: [MeasurementPoint],
        roomLabels: [RoomLabel] = [],
        accessPointNames: [String: String] = [:],
        configuration: HeatmapRenderer.Configuration = .init()
    ) {
        let renderer = HeatmapRenderer(configuration: configuration)
        let values = renderer.interpolateGrid(points: points, visualization: .signalStrength)
        let width = configuration.gridWidth, height = configuration.gridHeight
        let reach = HeatmapRenderer.falloffRadius * HeatmapRenderer.falloffRadius
        let grid: [[Double?]] = (0 ..< height).map { row in
            let y = Double(row) / max(Double(height - 1), 1)
            return (0 ..< width).map { col in
                let x = Double(col) / max(Double(width - 1), 1)
                let reached = points.contains { point in
                    let dx = point.floorPlanX - x, dy = point.floorPlanY - y
                    return dx * dx + dy * dy <= reach
                }
                return reached ? values[row][col] : nil
            }
        }
        self.init(
            grid: grid,
            pointCount: points.count,
            roomLabels: roomLabels,
            accessPoints: Self.accessPointShares(points, names: accessPointNames)
        )
    }

    // MARK: - Access points

    /// Display names of `devices` by normalized MAC, for naming access points.
    public static func accessPointNames(_ devices: [LocalDevice]) -> [String: String] {
        devices.reduce(into: [:]) { names, device in
            guard let mac = DeviceMatcher.normalizedMAC(device.macAddress) else { return }
            names[mac] = device.displayName
        }
    }

    /// How often each BSSID was the access point measured, among points that carry one.
    public static func accessPointShares(_ points: [MeasurementPoint], names: [String: String]) -> [AccessPointShare] {
        let bssids = points.compactMap { DeviceMatcher.normalizedMAC($0.bssid) }
        let counts: [String: Int] = bssids.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts
            .map { bssid, count in
                AccessPointShare(
                    name: names[bssid] ?? "access point ending :\(bssid.suffix(2))",
                    pointPercent: percent(count, of: bssids.count)
                )
            }
            .sorted { ($0.pointPercent, $1.name) > ($1.pointPercent, $0.name) }
    }

    // MARK: - Fall-off

    /// The compass direction from the strongest surveyed cells to the weakest, each taken as the
    /// centroid of the cells within 1 dB of the extreme, so a flat stretch of full signal doesn't
    /// pick an arbitrary corner. Nil when the extremes differ by under 1 dB.
    private static func falloff(in grid: [[Double?]]) -> Compass? {
        let cells = grid.enumerated().flatMap { row, values in
            values.enumerated().compactMap { col, value in value.map { (row: Double(row), col: Double(col), value: $0) } }
        }
        guard let high = cells.map(\.value).max(), let low = cells.map(\.value).min(), high - low >= 1 else { return nil }
        func centroid(_ near: (Double) -> Bool) -> (row: Double, col: Double) {
            let chosen = cells.filter { near($0.value) }
            let count = Double(chosen.count)
            return (chosen.map(\.row).reduce(0, +) / count, chosen.map(\.col).reduce(0, +) / count)
        }
        let strongest = centroid { $0 >= high - 1 }
        let weakest = centroid { $0 <= low + 1 }
        // Up is north, so the row difference is negated.
        let angle = atan2(strongest.row - weakest.row, weakest.col - strongest.col)
        let sector = Int(((angle / (.pi / 4)).rounded() + 8).truncatingRemainder(dividingBy: 8))
        let directions: [Compass] = [.east, .northEast, .north, .northWest, .west, .southWest, .south, .southEast]
        return directions[sector]
    }

    // MARK: - Weak regions

    private static func weakRegions(in grid: [[Double?]], surveyedCells: Int, roomLabels: [RoomLabel]) -> [WeakRegion] {
        let height = grid.count
        let width = grid.first?.count ?? 0
        func isWeak(_ row: Int, _ col: Int) -> Bool {
            grid[row][col].map { $0 < fairRSSI } ?? false
        }
        var seen = Array(repeating: Array(repeating: false, count: width), count: height)
        var regions: [(cells: [(row: Int, col: Int)], values: [Double])] = []
        for row in 0 ..< height {
            for col in 0 ..< width where isWeak(row, col) && !seen[row][col] {
                // Flood fill over all eight neighbours: an interpolated contour steps diagonally.
                var stack = [(row, col)]
                seen[row][col] = true
                var cells: [(row: Int, col: Int)] = []
                var values: [Double] = []
                while let (cellRow, cellCol) = stack.popLast() {
                    cells.append((cellRow, cellCol))
                    values.append(grid[cellRow][cellCol] ?? 0)
                    for (dr, dc) in [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)] {
                        let nr = cellRow + dr, nc = cellCol + dc
                        guard nr >= 0, nr < height, nc >= 0, nc < width, !seen[nr][nc], isWeak(nr, nc) else { continue }
                        seen[nr][nc] = true
                        stack.append((nr, nc))
                    }
                }
                regions.append((cells, values))
            }
        }
        return regions
            // A speck that rounds to 0% of the area is interpolation noise, not a region.
            .filter { percent($0.cells.count, of: surveyedCells) > 0 }
            .sorted { $0.cells.count > $1.cells.count }
            .prefix(maxWeakRegions)
            .map { region in
                let count = Double(region.cells.count)
                // Cell centres, normalized so the plan spans 0…1.
                let x = region.cells.map { (Double($0.col) + 0.5) / Double(width) }.reduce(0, +) / count
                let y = region.cells.map { (Double($0.row) + 0.5) / Double(height) }.reduce(0, +) / count
                return WeakRegion(
                    areaPercent: percent(region.cells.count, of: surveyedCells),
                    worstRSSI: Int((region.values.min() ?? 0).rounded()),
                    meanRSSI: Int((region.values.reduce(0, +) / count).rounded()),
                    location: location(x: x, y: y, roomLabels: roomLabels)
                )
            }
    }

    /// The labelled room nearest (`x`, `y`), else its compass position. A room label is a point,
    /// not an outline, so the nearest one stands for the room the region is in.
    private static func location(x: Double, y: Double, roomLabels: [RoomLabel]) -> Location {
        let nearest = roomLabels
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .min { distance($0, x, y) < distance($1, x, y) }
        return nearest.map { .room($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .compass(Compass(x: x, y: y))
    }

    private static func distance(_ label: RoomLabel, _ x: Double, _ y: Double) -> Double {
        let dx = label.normalizedX - x, dy = label.normalizedY - y
        return dx * dx + dy * dy
    }

    // MARK: - Helpers

    static func percent(_ part: Int, of total: Int) -> Int {
        Int((Double(part) * 100 / Double(max(total, 1))).rounded())
    }
}
