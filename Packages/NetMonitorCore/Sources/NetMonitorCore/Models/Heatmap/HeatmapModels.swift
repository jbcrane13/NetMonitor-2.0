import Foundation

// MARK: - SurveyMode

public enum SurveyMode: String, Sendable, Codable, CaseIterable {
    case blueprint
    case arAssisted
    case arContinuous
}

// MARK: - SurveyMetadata

public struct SurveyMetadata: Sendable, Codable, Equatable {
    public var buildingName: String?
    public var floorNumber: String?
    public var notes: String?

    public init(
        buildingName: String? = nil,
        floorNumber: String? = nil,
        notes: String? = nil
    ) {
        self.buildingName = buildingName
        self.floorNumber = floorNumber
        self.notes = notes
    }
}

// MARK: - FloorPlanOrigin

public enum FloorPlanOrigin: String, Sendable, Codable, Equatable {
    case imported
    case arGenerated
    case drawn
}

// MARK: - CalibrationPoint

public struct CalibrationPoint: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var pixelX: Double
    public var pixelY: Double
    public var realWorldX: Double
    public var realWorldY: Double

    public init(
        id: UUID = UUID(),
        pixelX: Double,
        pixelY: Double,
        realWorldX: Double = 0,
        realWorldY: Double = 0
    ) {
        self.id = id
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.realWorldX = realWorldX
        self.realWorldY = realWorldY
    }

    public static func metersPerPixel(
        pointA: CalibrationPoint,
        pointB: CalibrationPoint,
        knownDistanceMeters: Double
    ) -> Double {
        let dx = pointA.pixelX - pointB.pixelX
        let dy = pointA.pixelY - pointB.pixelY
        let pixelDistance = (dx * dx + dy * dy).squareRoot()
        guard pixelDistance > 0 else { return 0 }
        return knownDistanceMeters / pixelDistance
    }
}

// MARK: - WallSegment

public struct WallSegment: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double
    public var thickness: Double

    public init(
        id: UUID = UUID(),
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        thickness: Double = 0.15
    ) {
        self.id = id
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.thickness = thickness
    }
}

// MARK: - FloorPlan

public struct FloorPlan: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var imageData: Data
    public var widthMeters: Double
    public var heightMeters: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var origin: FloorPlanOrigin
    public var calibrationPoints: [CalibrationPoint]?
    public var walls: [WallSegment]?

    public init(
        id: UUID = UUID(),
        imageData: Data,
        widthMeters: Double,
        heightMeters: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        origin: FloorPlanOrigin = .imported,
        calibrationPoints: [CalibrationPoint]? = nil,
        walls: [WallSegment]? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.origin = origin
        self.calibrationPoints = calibrationPoints
        self.walls = walls
    }

    public var metersPerPixelX: Double {
        guard pixelWidth > 0 else { return 0 }
        return widthMeters / Double(pixelWidth)
    }

    public var metersPerPixelY: Double {
        guard pixelHeight > 0 else { return 0 }
        return heightMeters / Double(pixelHeight)
    }
}

// MARK: - MeasurementPoint

public struct MeasurementPoint: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public var floorPlanX: Double
    public var floorPlanY: Double
    public var rssi: Int
    public var noiseFloor: Int?
    public var snr: Int?
    public var ssid: String?
    public var bssid: String?
    public var channel: Int?
    public var frequency: Double?
    public var band: WiFiBand?
    public var linkSpeed: Int?
    public var downloadSpeed: Double?
    public var uploadSpeed: Double?
    public var latency: Double?
    public var connectedAPName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        floorPlanX: Double = 0,
        floorPlanY: Double = 0,
        rssi: Int = -100,
        noiseFloor: Int? = nil,
        snr: Int? = nil,
        ssid: String? = nil,
        bssid: String? = nil,
        channel: Int? = nil,
        frequency: Double? = nil,
        band: WiFiBand? = nil,
        linkSpeed: Int? = nil,
        downloadSpeed: Double? = nil,
        uploadSpeed: Double? = nil,
        latency: Double? = nil,
        connectedAPName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.floorPlanX = floorPlanX
        self.floorPlanY = floorPlanY
        self.rssi = rssi
        self.noiseFloor = noiseFloor
        self.snr = snr
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.frequency = frequency
        self.band = band
        self.linkSpeed = linkSpeed
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.connectedAPName = connectedAPName
    }
}

// MARK: - HeatmapVisualization

public enum HeatmapVisualization: String, Sendable, Codable, CaseIterable {
    case signalStrength
    case signalToNoise
    case noiseFloor
    case downloadSpeed
    case uploadSpeed
    case latency
    case frequencyBand

    public var displayName: String {
        switch self {
        case .signalStrength: "Signal Strength"
        case .signalToNoise: "Signal-to-Noise"
        case .noiseFloor: "Noise Floor"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .latency: "Latency"
        case .frequencyBand: "Frequency Band"
        }
    }

    public var unit: String {
        switch self {
        case .signalStrength: "dBm"
        case .signalToNoise: "dB"
        case .noiseFloor: "dBm"
        case .downloadSpeed: "Mbps"
        case .uploadSpeed: "Mbps"
        case .latency: "ms"
        case .frequencyBand: "GHz"
        }
    }

    /// Whether this visualization requires active scan data (speed test / ping)
    public var requiresActiveScan: Bool {
        switch self {
        case .downloadSpeed, .uploadSpeed, .latency:
            return true
        case .signalStrength, .signalToNoise, .noiseFloor, .frequencyBand:
            return false
        }
    }

    public func extractValue(from point: MeasurementPoint) -> Double? {
        switch self {
        case .signalStrength:
            return Double(point.rssi)
        case .signalToNoise:
            return point.snr.map(Double.init)
        case .noiseFloor:
            return point.noiseFloor.map(Double.init)
        case .downloadSpeed:
            return point.downloadSpeed
        case .uploadSpeed:
            return point.uploadSpeed
        case .latency:
            return point.latency
        case .frequencyBand:
            // 2.4 GHz → 1, 5 GHz → 2, 6 GHz → 3
            guard let band = point.band else { return nil }
            switch band {
            case .band2_4GHz: return 1.0
            case .band5GHz: return 2.0
            case .band6GHz: return 3.0
            }
        }
    }

    public var valueRange: ClosedRange<Double> {
        switch self {
        case .signalStrength: -100...0
        case .signalToNoise: 0...50
        case .noiseFloor: -100 ... -60
        case .downloadSpeed: 0...500
        case .uploadSpeed: 0...500
        case .latency: 0...200
        case .frequencyBand: 0...4
        }
    }

    public var isHigherBetter: Bool {
        switch self {
        case .signalStrength, .signalToNoise, .downloadSpeed, .uploadSpeed:
            return true
        case .noiseFloor, .latency:
            return false
        case .frequencyBand:
            return true
        }
    }

    /// Check whether the given points have data for this visualization
    public func hasData(in points: [MeasurementPoint]) -> Bool {
        points.contains { extractValue(from: $0) != nil }
    }
}

// MARK: - HeatmapColorScheme

public enum HeatmapColorScheme: String, Sendable, Codable, CaseIterable {
    case thermal
    case stoplight
    case plasma
    /// WiFiman-style: green (strong) → yellow → red (weak), matching familiar network app conventions.
    case wifiman

    public var displayName: String {
        switch self {
        case .thermal: "Thermal"
        case .stoplight: "Stoplight"
        case .plasma: "Plasma"
        case .wifiman: "WiFiman"
        }
    }
}

// MARK: - SurveyProject

public struct SurveyProject: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var floorPlan: FloorPlan
    public var measurementPoints: [MeasurementPoint]
    public var surveyMode: SurveyMode
    public var metadata: SurveyMetadata

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        floorPlan: FloorPlan,
        measurementPoints: [MeasurementPoint] = [],
        surveyMode: SurveyMode = .blueprint,
        metadata: SurveyMetadata = SurveyMetadata()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.floorPlan = floorPlan
        self.measurementPoints = measurementPoints
        self.surveyMode = surveyMode
        self.metadata = metadata
    }

    public var averageRSSI: Double? {
        guard !measurementPoints.isEmpty else { return nil }
        let sum = measurementPoints.reduce(0) { $0 + $1.rssi }
        return Double(sum) / Double(measurementPoints.count)
    }

    public var minRSSI: Int? {
        measurementPoints.map(\.rssi).min()
    }

    public var maxRSSI: Int? {
        measurementPoints.map(\.rssi).max()
    }
}
