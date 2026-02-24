import Foundation

// MARK: - HeatmapMode

/// Survey mode for WiFi heatmapping.
public enum HeatmapMode: String, Codable, CaseIterable, Sendable {
    case freeform  = "freeform"   // Walk around; tap anywhere to record
    case floorplan = "floorplan"  // Import floor plan image; tap to record positions

    public var displayName: String {
        switch self {
        case .freeform:  "Freeform"
        case .floorplan: "Floorplan"
        }
    }

    public var systemImage: String {
        switch self {
        case .freeform:  "hand.tap"
        case .floorplan: "map"
        }
    }

    public var description: String {
        switch self {
        case .freeform:  "Tap anywhere on the canvas to record signal strength at that position"
        case .floorplan: "Import a floor plan image and tap positions while walking"
        }
    }
}

// MARK: - SignalLevel

/// Categorises WiFi RSSI into display buckets.
public enum SignalLevel: Sendable {
    case strong  // ≥ -50 dBm
    case fair    // -70 to -51 dBm
    case weak    // < -70 dBm

    public static func from(rssi: Int) -> SignalLevel {
        switch rssi {
        case (-50)...:      return .strong
        case (-70)...(-51): return .fair
        default:            return .weak
        }
    }

    /// Hex color string for canvas rendering (no SwiftUI dependency).
    public var hexColor: String {
        switch self {
        case .strong: "00C853"
        case .fair:   "FFD600"
        case .weak:   "D50000"
        }
    }

    public var label: String {
        switch self {
        case .strong: "Strong"
        case .fair:   "Fair"
        case .weak:   "Weak"
        }
    }
}

// MARK: - HeatmapSurvey

// HeatmapDataPoint (declared in ServiceProtocols.swift) already conforms to Sendable, Codable.

/// A recorded WiFi signal survey session with its data points.
public struct HeatmapSurvey: Identifiable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let mode: HeatmapMode
    public let createdAt: Date
    public var dataPoints: [HeatmapDataPoint]

    public init(
        id: UUID = UUID(),
        name: String,
        mode: HeatmapMode = .freeform,
        createdAt: Date = Date(),
        dataPoints: [HeatmapDataPoint] = []
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.dataPoints = dataPoints
    }

    /// Average signal strength across all recorded data points.
    public var averageSignal: Int? {
        guard !dataPoints.isEmpty else { return nil }
        let total = dataPoints.reduce(0) { $0 + $1.signalStrength }
        return total / dataPoints.count
    }

    /// Overall signal quality for this survey.
    public var signalLevel: SignalLevel? {
        guard let avg = averageSignal else { return nil }
        return SignalLevel.from(rssi: avg)
    }
}
