import Foundation

// MARK: - SurveyProject

/// Root model for a WiFi heatmap survey project.
/// Contains a floor plan, measurement points, survey mode, and optional metadata.
public struct SurveyProject: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public var floorPlan: FloorPlan
    public var measurementPoints: [MeasurementPoint]
    public var surveyMode: SurveyMode
    public var metadata: SurveyMetadata?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        floorPlan: FloorPlan,
        measurementPoints: [MeasurementPoint] = [],
        surveyMode: SurveyMode = .blueprint,
        metadata: SurveyMetadata? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.floorPlan = floorPlan
        self.measurementPoints = measurementPoints
        self.surveyMode = surveyMode
        self.metadata = metadata
    }
}

// MARK: - FloorPlan

/// Represents the floor plan image and its real-world dimensions.
/// Coordinates are in pixels; `widthMeters` / `heightMeters` provide the
/// real-world scale (zero until calibrated).
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
        origin: FloorPlanOrigin,
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
}

// MARK: - MeasurementPoint

/// A single WiFi measurement taken at a specific location on the floor plan.
/// `floorPlanX` and `floorPlanY` are normalized to 0.0–1.0 range.
public struct MeasurementPoint: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let floorPlanX: Double
    public let floorPlanY: Double
    public let rssi: Int
    public let noiseFloor: Int?
    public let snr: Int?
    public let ssid: String?
    public let bssid: String?
    public let channel: Int?
    public let frequency: Int?
    public let band: WiFiBand?
    public let linkSpeed: Int?
    public let downloadSpeed: Double?
    public let uploadSpeed: Double?
    public let latency: Double?
    public let connectedAPName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        floorPlanX: Double,
        floorPlanY: Double,
        rssi: Int,
        noiseFloor: Int? = nil,
        snr: Int? = nil,
        ssid: String? = nil,
        bssid: String? = nil,
        channel: Int? = nil,
        frequency: Int? = nil,
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

// MARK: - CalibrationPoint

/// A mapping between a pixel location on the floor plan image
/// and its corresponding real-world coordinates (in meters).
public struct CalibrationPoint: Sendable, Codable, Equatable {
    public let pixelX: Double
    public let pixelY: Double
    public let realWorldX: Double
    public let realWorldY: Double

    public init(pixelX: Double, pixelY: Double, realWorldX: Double, realWorldY: Double) {
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.realWorldX = realWorldX
        self.realWorldY = realWorldY
    }
}

// MARK: - WallSegment

/// A line segment representing a wall on the floor plan,
/// defined in real-world coordinates (meters).
public struct WallSegment: Sendable, Codable, Equatable {
    public let startX: Double
    public let startY: Double
    public let endX: Double
    public let endY: Double
    public let thickness: Double

    public init(startX: Double, startY: Double, endX: Double, endY: Double, thickness: Double) {
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.thickness = thickness
    }
}

// MARK: - SurveyMetadata

/// Optional metadata about the survey location.
public struct SurveyMetadata: Sendable, Codable, Equatable {
    public let buildingName: String?
    public let floorNumber: Int?
    public let notes: String?

    public init(buildingName: String? = nil, floorNumber: Int? = nil, notes: String? = nil) {
        self.buildingName = buildingName
        self.floorNumber = floorNumber
        self.notes = notes
    }
}
