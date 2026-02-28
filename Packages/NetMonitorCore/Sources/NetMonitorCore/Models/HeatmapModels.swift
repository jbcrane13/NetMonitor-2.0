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

// MARK: - DistanceUnit

public enum DistanceUnit: String, Codable, CaseIterable, Sendable, Equatable {
    case feet   = "ft"
    case meters = "m"

    public var displayName: String { rawValue }

    /// Convert `value` (in `self` units) to `target` units.
    public func convert(_ value: Double, to target: DistanceUnit) -> Double {
        guard self != target else { return value }
        return self == .feet ? value * 0.3048 : value / 0.3048
    }
}

// MARK: - CalibrationScale

/// Scale established by the user drawing a reference line on the floor plan.
public struct CalibrationScale: Codable, Sendable, Equatable {
    public let pixelDistance: Double   // px length of the drawn reference line
    public let realDistance: Double    // real-world distance entered by the user
    public let unit: DistanceUnit

    public init(pixelDistance: Double, realDistance: Double, unit: DistanceUnit) {
        self.pixelDistance = pixelDistance
        self.realDistance = realDistance
        self.unit = unit
    }

    public var pixelsPerUnit: Double { pixelDistance / realDistance }

    /// Convert a pixel distance to real-world units.
    public func realDistance(pixels: Double) -> Double { pixels / pixelsPerUnit }
}

// MARK: - HeatmapColorScheme

/// Color mapping for heatmap gradient rendering.
public enum HeatmapColorScheme: String, Codable, CaseIterable, Sendable, Equatable {
    case thermal = "thermal"  // blue → cyan → green → yellow → red (DEFAULT)
    case signal  = "signal"   // red → orange → yellow → green
    case nebula  = "nebula"   // navy → violet → magenta → white
    case arctic  = "arctic"   // navy → teal → ice blue → white

    public var displayName: String {
        switch self {
        case .thermal: "Thermal"
        case .signal:  "Signal"
        case .nebula:  "Nebula"
        case .arctic:  "Arctic"
        }
    }

    /// Color stops: (t: 0–1, hexRGB string). t=0 is weakest signal, t=1 is strongest.
    public var colorStops: [(t: Double, hex: String)] {
        switch self {
        case .thermal:
            return [(0, "000080"), (0.15, "0000ff"), (0.30, "00ffff"),
                    (0.50, "00ff00"), (0.70, "ffff00"), (0.85, "ff8800"), (1.0, "ff0000")]
        case .signal:
            return [(0, "cc0000"), (0.25, "ff4400"), (0.50, "ffcc00"),
                    (0.75, "88ff00"), (1.0, "00dd44")]
        case .nebula:
            return [(0, "0a0a2a"), (0.20, "1a0060"), (0.40, "6600aa"),
                    (0.60, "cc00aa"), (0.80, "ff44cc"), (1.0, "ffffff")]
        case .arctic:
            return [(0, "050a14"), (0.20, "062040"), (0.40, "0a4060"),
                    (0.60, "1088aa"), (0.80, "44ccdd"), (1.0, "ffffff")]
        }
    }
}

// MARK: - HeatmapDisplayOverlay

/// Bit-mask of active rendering overlays. Multiple may be combined.
public struct HeatmapDisplayOverlay: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let gradient  = HeatmapDisplayOverlay(rawValue: 1 << 0)  // default ON
    public static let dots      = HeatmapDisplayOverlay(rawValue: 1 << 1)
    public static let contour   = HeatmapDisplayOverlay(rawValue: 1 << 2)
    public static let deadZones = HeatmapDisplayOverlay(rawValue: 1 << 3)
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
        case -70...(-51): return .fair
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
    public var calibration: CalibrationScale?

    public init(
        id: UUID = UUID(),
        name: String,
        mode: HeatmapMode = .freeform,
        createdAt: Date = Date(),
        dataPoints: [HeatmapDataPoint] = [],
        calibration: CalibrationScale? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.dataPoints = dataPoints
        self.calibration = calibration
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
