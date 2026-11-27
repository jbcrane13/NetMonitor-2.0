import Foundation
import NetworkScanKit

/// The evidence the model reads about a device (#586): bounded prompt lines, the same whether this
/// device's model reads them or the Mac's. The phone sends exactly these lines for `identity.v1`,
/// and the Mac checks them again (`init?(lines:)`) and builds the very prompt the local model gets.
///
/// Only names, services, ports, the MAC-prefix maker and the known maker, model and type go in:
/// never notes, addresses, MACs or the device list.
public struct DeviceEvidenceProjection: Sendable, Equatable, Codable {
    /// The longest line: `DeviceEvidence.lineLimit` plus the "…" that marks a cut.
    public static let lineLimit = DeviceEvidence.lineLimit + 1

    /// The labels a line may start with, each at most once. The service and port lines carry a
    /// count after their label: "Network services (3): …".
    static let labels = [
        "Name given by the user", "Name the device announces", "Hostname", "Reverse DNS name", "MAC address maker",
        "Maker the device announces", "Model", "Type", "Network services", "Open ports"
    ]

    public let lines: [String]

    /// The lines for `evidence`, as `DeviceEvidence.promptLines` builds them.
    init(evidence: DeviceEvidence) {
        lines = evidence.promptLines
    }

    /// Lines from the wire, or nil when they aren't evidence lines this build writes: empty, more
    /// than one per label, a label it doesn't know, a line break, or a line over the bound.
    public init?(lines: [String]) {
        guard !lines.isEmpty, lines.count <= Self.labels.count else { return nil }
        var seen: Set<String> = []
        for line in lines {
            guard line.count <= Self.lineLimit, !line.contains(where: \.isNewline),
                  let label = Self.label(of: line), Self.labels.contains(label), seen.insert(label).inserted
            else { return nil }
        }
        self.lines = lines
    }

    /// The prompt the model reads.
    public var prompt: String {
        (["Evidence about the device:"] + lines.map { "- " + $0 } + ["Suggest its type, maker and model."])
            .joined(separator: "\n")
    }

    /// The label before ": ", without a "(count)" after it.
    private static func label(of line: String) -> String? {
        guard let colon = line.range(of: ": ") else { return nil }
        var label = String(line[..<colon.lowerBound])
        if label.hasSuffix(")"), let open = label.lastIndex(of: "("),
           label[label.index(after: open) ..< label.index(before: label.endIndex)].allSatisfy(\.isNumber) {
            label = String(label[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return label
    }

    private enum CodingKeys: String, CodingKey {
        case lines
    }

    public init(from decoder: any Decoder) throws {
        let lines = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .lines)
        guard let projection = DeviceEvidenceProjection(lines: lines) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not evidence lines"))
        }
        self = projection
    }
}

extension DeviceEvidence {
    /// What the model reads about this device, on this device or the Mac.
    public var projection: DeviceEvidenceProjection {
        DeviceEvidenceProjection(evidence: self)
    }
}

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
