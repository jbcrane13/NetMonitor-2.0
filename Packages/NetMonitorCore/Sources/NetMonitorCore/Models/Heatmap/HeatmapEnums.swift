import Foundation

// MARK: - FloorPlanOrigin

/// How the floor plan was created or obtained.
/// Uses explicit Codable conformance to handle the `.imported(URL)` associated value.
public enum FloorPlanOrigin: Sendable, Equatable {
    case imported(URL)
    case arGenerated
    case drawn
}

// MARK: - FloorPlanOrigin + Codable

extension FloorPlanOrigin: Codable {

    private enum CodingKeys: String, CodingKey {
        case type
        case url
    }

    private enum OriginType: String, Codable {
        case imported
        case arGenerated
        case drawn
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .imported(let url):
            try container.encode(OriginType.imported, forKey: .type)
            try container.encode(url, forKey: .url)
        case .arGenerated:
            try container.encode(OriginType.arGenerated, forKey: .type)
        case .drawn:
            try container.encode(OriginType.drawn, forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(OriginType.self, forKey: .type)
        switch type {
        case .imported:
            let url = try container.decode(URL.self, forKey: .url)
            self = .imported(url)
        case .arGenerated:
            self = .arGenerated
        case .drawn:
            self = .drawn
        }
    }
}

// MARK: - SurveyMode

/// The survey methodology used for the project.
/// Raw values are stable strings for forward-compatible serialization.
public enum SurveyMode: String, Sendable, Codable, CaseIterable, Equatable {
    case blueprint = "blueprint"
    case arAssisted = "arAssisted"
    case arContinuous = "arContinuous"
}

// MARK: - HeatmapVisualization

/// The metric being visualized on the heatmap overlay.
/// Raw values are stable strings for forward-compatible serialization.
public enum HeatmapVisualization: String, Sendable, Codable, CaseIterable, Equatable {
    case signalStrength = "signalStrength"
    case signalToNoise = "signalToNoise"
    case downloadSpeed = "downloadSpeed"
    case uploadSpeed = "uploadSpeed"
    case latency = "latency"

    /// Human-readable display name for the visualization type.
    public var displayName: String {
        switch self {
        case .signalStrength: "Signal Strength"
        case .signalToNoise: "Signal-to-Noise"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .latency: "Latency"
        }
    }
}
