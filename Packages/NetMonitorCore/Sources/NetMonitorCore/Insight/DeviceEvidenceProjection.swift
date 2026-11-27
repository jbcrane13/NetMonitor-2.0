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
    /// The most bytes all lines may take together (#642 review): every line at its character bound
    /// in four-byte characters, so nothing the phone builds goes over, and nothing larger comes in.
    public static let byteLimit = labels.count * lineLimit * 4

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
    /// than one per label, a label it doesn't know, a line break, a line over the bound, over
    /// `byteLimit` in all, or a service or port list whose count doesn't match what it lists.
    ///
    /// Names and hostnames are free text the device or the user chose, and may hold anything, an
    /// address included: the local model reads the same text, and the consent covers names.
    public init?(lines: [String]) {
        guard !lines.isEmpty, lines.count <= Self.labels.count, lines.reduce(0, { $0 + $1.utf8.count }) <= Self.byteLimit else {
            return nil
        }
        var seen: Set<String> = []
        for line in lines {
            guard line.count <= Self.lineLimit, !line.contains(where: \.isNewline),
                  let label = Self.label(of: line), Self.labels.contains(label), seen.insert(label).inserted,
                  Self.isConsistentList(line, label: label)
            else { return nil }
        }
        self.lines = lines
    }

    /// For "Network services (N): …" and "Open ports (N): …": one to `DeviceEvidence.listLimit`
    /// items, then "and K more" for what didn't fit, N equal to what's listed plus K, and ports as
    /// numbers. Any other line is consistent.
    private static func isConsistentList(_ line: String, label: String) -> Bool {
        guard label == "Network services" || label == "Open ports" else { return true }
        guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close,
              let count = Int(line[line.index(after: open) ..< close]), let colon = line.range(of: ": ")
        else { return false }
        var items = line[colon.upperBound...].components(separatedBy: ", ")
        var more = 0
        if let last = items.last, last.hasPrefix("and "), last.hasSuffix(" more"),
           let number = Int(last.dropFirst(4).dropLast(5)) {
            more = number
            items.removeLast()
        }
        guard (1 ... DeviceEvidence.listLimit).contains(items.count), count == items.count + more, more >= 0 else { return false }
        return label == "Network services" || items.allSatisfy { Int($0) != nil }
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
