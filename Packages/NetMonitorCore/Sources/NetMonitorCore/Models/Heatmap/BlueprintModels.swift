import Foundation

// MARK: - BlueprintProject

/// Top-level container for a .netmonblueprint file.
/// Contains one or more floor scans from RoomPlan, each with an SVG floor plan
/// and scale metadata. iPhone scans the room; macOS imports the blueprint
/// as a pre-calibrated base map for Wi-Fi heatmap surveys.
public struct BlueprintProject: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var floors: [BlueprintFloor]
    public var metadata: BlueprintMetadata

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        floors: [BlueprintFloor] = [],
        metadata: BlueprintMetadata = BlueprintMetadata()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.floors = floors
        self.metadata = metadata
    }
}

// MARK: - BlueprintFloor

/// A single floor scan with its SVG floor plan, scale, and room labels.
public struct BlueprintFloor: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var label: String
    public var floorNumber: Int
    public var svgData: Data
    public var widthMeters: Double
    public var heightMeters: Double
    public var roomLabels: [RoomLabel]
    public var wallSegments: [WallSegment]

    public init(
        id: UUID = UUID(),
        label: String = "Floor 1",
        floorNumber: Int = 1,
        svgData: Data = Data(),
        widthMeters: Double = 0,
        heightMeters: Double = 0,
        roomLabels: [RoomLabel] = [],
        wallSegments: [WallSegment] = []
    ) {
        self.id = id
        self.label = label
        self.floorNumber = floorNumber
        self.svgData = svgData
        self.widthMeters = widthMeters
        self.heightMeters = heightMeters
        self.roomLabels = roomLabels
        self.wallSegments = wallSegments
    }
}

// MARK: - RoomLabel

/// A user-visible label placed at a position on the floor plan.
public struct RoomLabel: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    /// Normalized X position (0.0-1.0) on the floor plan
    public var normalizedX: Double
    /// Normalized Y position (0.0-1.0) on the floor plan
    public var normalizedY: Double

    public init(
        id: UUID = UUID(),
        text: String,
        normalizedX: Double,
        normalizedY: Double
    ) {
        self.id = id
        self.text = text
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

// MARK: - BlueprintMetadata

/// Metadata about the scan session.
public struct BlueprintMetadata: Sendable, Codable, Equatable {
    public var buildingName: String?
    public var address: String?
    public var notes: String?
    public var scanDeviceModel: String?
    public var hasLiDAR: Bool

    public init(
        buildingName: String? = nil,
        address: String? = nil,
        notes: String? = nil,
        scanDeviceModel: String? = nil,
        hasLiDAR: Bool = false
    ) {
        self.buildingName = buildingName
        self.address = address
        self.notes = notes
        self.scanDeviceModel = scanDeviceModel
        self.hasLiDAR = hasLiDAR
    }
}
