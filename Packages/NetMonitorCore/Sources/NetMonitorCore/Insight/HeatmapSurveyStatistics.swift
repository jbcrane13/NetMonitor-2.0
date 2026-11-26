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

    /// How often one access point was the one a measurement was connected to. A share of
    /// associations, not a measure of which access point had the strongest signal.
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
    /// Grid cells inside the surveyed area; 0 when no cell is.
    public let surveyedCells: Int
    public let coverage: Coverage
    /// Every weak region that isn't a speck, before `weakRegions` keeps the largest.
    public let weakRegionCount: Int
    /// Up to `maxWeakRegions`, largest first.
    public let weakRegions: [WeakRegion]
    /// The direction signal falls off in, from the strongest cells toward the weakest; nil when
    /// the grid is even or the two lie within a cell of each other.
    public let falloff: Compass?
    /// Largest share first; empty when no point carries a BSSID.
    public let accessPoints: [AccessPointShare]

    // MARK: - Init

    /// Statistics of `grid`, signal in dBm per cell, nil outside the surveyed area. Cell (`row`,
    /// `col`) lies at (`col / (width - 1)`, `row / (height - 1)`) on the plan, where the renderer
    /// samples it. A weak region is named after the labelled room nearest its centroid, measured
    /// in metres on a plan of `planWidth` × `planHeight`, when the plan has room labels.
    public init(
        grid: [[Double?]],
        pointCount: Int,
        roomLabels: [RoomLabel] = [],
        planWidth: Double = 1,
        planHeight: Double = 1,
        accessPoints: [AccessPointShare] = []
    ) {
        self.pointCount = pointCount
        self.accessPoints = accessPoints
        let cells = grid.flatMap { $0 }.compactMap { $0 }
        surveyedCells = cells.count
        let good = cells.count { $0 >= Self.goodRSSI }
        let weak = cells.count { $0 < Self.fairRSSI }
        coverage = Coverage(
            good: Self.percent(good, of: cells.count),
            fair: Self.percent(cells.count - good - weak, of: cells.count),
            weak: Self.percent(weak, of: cells.count)
        )
        let regions = Self.weakRegions(in: grid, surveyedCells: cells.count, plan: Plan(rooms: roomLabels, width: planWidth, height: planHeight))
        weakRegionCount = regions.count
        weakRegions = Array(regions.prefix(Self.maxWeakRegions))
        falloff = Self.falloff(in: grid)
    }

    /// Statistics of a survey's `points` on `floorPlan`, on the grid `HeatmapRenderer`
    /// interpolates with `configuration`. Only cells the renderer draws, within
    /// `HeatmapRenderer.falloffRadius` of a point, are the surveyed area.
    /// - Parameter accessPointNames: device display names by normalized MAC (`accessPointNames(_:)`).
    public init(
        points: [MeasurementPoint],
        floorPlan: FloorPlan? = nil,
        accessPointNames: [String: String] = [:],
        configuration: HeatmapRenderer.Configuration = .init()
    ) {
        let renderer = HeatmapRenderer(configuration: configuration)
        let values = renderer.interpolateGrid(points: points, visualization: .signalStrength)
        let width = configuration.gridWidth, height = configuration.gridHeight
        let reach = HeatmapRenderer.falloffRadius * HeatmapRenderer.falloffRadius
        let grid: [[Double?]] = (0 ..< height).map { row in
            let y = Self.position(row, of: height)
            return (0 ..< width).map { col in
                let x = Self.position(col, of: width)
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
            roomLabels: floorPlan?.roomLabels ?? [],
            planWidth: floorPlan?.widthMeters ?? 1,
            planHeight: floorPlan?.heightMeters ?? 1,
            accessPoints: Self.accessPointShares(points, names: accessPointNames)
        )
    }

    // MARK: - Access points

    /// Display names of `devices` by every member's normalized MAC, for naming access points; an
    /// interface is named by its device (#594).
    public static func accessPointNames(_ devices: [LocalDevice]) -> [String: String] {
        DeviceGroups.project(devices).reduce(into: [:]) { names, device in
            for member in device.members {
                guard let mac = DeviceMatcher.normalizedMAC(member.macAddress) else { continue }
                names[mac] = device.displayName
            }
        }
    }

    /// How often each BSSID was the access point a measurement was connected to, among points
    /// that carry one.
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
    /// pick an arbitrary corner. Measured on the plan's 0…1 axes. Nil when the extremes differ by
    /// under 1 dB, or the centroids are within a cell of each other: weak areas on both sides of
    /// a strong middle have no single direction.
    private static func falloff(in grid: [[Double?]]) -> Compass? {
        let height = grid.count, width = grid.first?.count ?? 0
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
        guard abs(weakest.col - strongest.col) > 1 || abs(weakest.row - strongest.row) > 1 else { return nil }
        // On the plan's axes, so a wide grid doesn't tilt the direction; up is north.
        let east = (weakest.col - strongest.col) / Double(max(width - 1, 1))
        let north = (strongest.row - weakest.row) / Double(max(height - 1, 1))
        let sector = Int(((atan2(north, east) / (.pi / 4)).rounded() + 8).truncatingRemainder(dividingBy: 8))
        let directions: [Compass] = [.east, .northEast, .north, .northWest, .west, .southWest, .south, .southEast]
        return directions[sector]
    }

    // MARK: - Weak regions

    /// The room labels and size of the plan regions are placed on.
    private struct Plan {
        let rooms: [RoomLabel]
        let width: Double
        let height: Double
    }

    /// Every weak region that isn't a speck, largest first.
    private static func weakRegions(in grid: [[Double?]], surveyedCells: Int, plan: Plan) -> [WeakRegion] {
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
            .map { region in
                let count = Double(region.cells.count)
                let x = region.cells.map { position($0.col, of: width) }.reduce(0, +) / count
                let y = region.cells.map { position($0.row, of: height) }.reduce(0, +) / count
                return WeakRegion(
                    areaPercent: percent(region.cells.count, of: surveyedCells),
                    worstRSSI: Int((region.values.min() ?? 0).rounded()),
                    meanRSSI: Int((region.values.reduce(0, +) / count).rounded()),
                    location: location(x: x, y: y, plan: plan)
                )
            }
    }

    /// The labelled room nearest (`x`, `y`), else its compass position. A room label is a point,
    /// not an outline, so the nearest one stands for the room the region is in.
    private static func location(x: Double, y: Double, plan: Plan) -> Location {
        func metres(_ label: RoomLabel) -> Double {
            let dx = (label.normalizedX - x) * plan.width, dy = (label.normalizedY - y) * plan.height
            return dx * dx + dy * dy
        }
        let nearest = plan.rooms
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .min { metres($0) < metres($1) }
        return nearest.map { .room($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .compass(Compass(x: x, y: y))
    }

    // MARK: - Helpers

    /// Where index `index` of `count` samples lies on a 0…1 axis, as the renderer samples it.
    static func position(_ index: Int, of count: Int) -> Double {
        Double(index) / max(Double(count - 1), 1)
    }

    static func percent(_ part: Int, of total: Int) -> Int {
        Int((Double(part) * 100 / Double(max(total, 1))).rounded())
    }
}
