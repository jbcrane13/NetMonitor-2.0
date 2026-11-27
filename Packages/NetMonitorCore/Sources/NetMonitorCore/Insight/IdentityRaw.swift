import Foundation
import NetworkScanKit

/// The model's unchecked identity answer (#586): what `identity.v1` carries back. The phone reads
/// it into a ``DeviceSuggestion`` and checks it as it checks its own model's.
public struct IdentityRaw: Codable, Sendable, Equatable {
    public var deviceType: String
    public var maker: String?
    public var model: String?
    public var confidence: String

    public init(deviceType: String, maker: String? = nil, model: String? = nil, confidence: String) {
        self.deviceType = deviceType
        self.maker = maker
        self.model = model
        self.confidence = confidence
    }

    /// Whether every field is within its bound: a longer one fails the answer, never cut.
    public var isWithinLimits: Bool {
        deviceType.count <= ModelSchema.kindLimit && confidence.count <= ModelSchema.kindLimit
            && [maker, model].allSatisfy { ($0?.count ?? 0) <= ModelSchema.fieldLimit }
    }

    /// The suggestion, marked as written by `source`. An unknown type or an empty text is none,
    /// and an unknown confidence is low.
    public func suggestion(from source: InsightSource) -> DeviceSuggestion {
        func present(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        let type = DeviceType(rawValue: deviceType)
        return DeviceSuggestion(
            deviceType: type == .unknown ? nil : type,
            maker: present(maker),
            model: present(model),
            confidence: DeviceSuggestion.Confidence(rawValue: confidence) ?? .low,
            source: source
        )
    }
}
