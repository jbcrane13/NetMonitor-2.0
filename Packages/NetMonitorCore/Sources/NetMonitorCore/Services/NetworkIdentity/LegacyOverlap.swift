import Foundation
import NetworkScanKit

/// Whether a legacy network's saved devices clearly match what the identification probe saw, so its
/// history can be bound to this router without asking (#628 PR B). Portable devices prove the devices
/// are the same, not the site, so the check is site-anchored:
/// - the device answering at the routed gateway's address matches the saved row at that address, by a
///   real (globally administered) MAC or by a normalised, non-generic name;
/// - and at least 2 other distinct saved devices match one-to-one: by a real MAC at any address, or
///   by a non-generic name at the same address. A saved device of several interfaces counts once.
/// Otherwise the app asks. Names come only from the probe's own replies, never from saved rows.
public enum LegacyOverlap {
    public struct Observation: Sendable, Equatable {
        public let ipAddress: String
        public let macAddress: String?
        public let name: String?

        public init(ipAddress: String, macAddress: String?, name: String?) {
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.name = name
        }
    }

    public struct SavedDevice: Sendable, Equatable {
        /// The device's ID: its group's when it has several interfaces, else its row's.
        public let deviceID: UUID
        public let ipAddress: String
        public let macAddress: String?
        public let name: String?

        public init(deviceID: UUID, ipAddress: String, macAddress: String?, name: String?) {
            self.deviceID = deviceID
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.name = name
        }
    }

    /// Matches beyond the gateway needed for a quiet bind.
    public static let othersNeeded = 2

    public static func isClear(gatewayIP: String, observed: [Observation], saved: [SavedDevice]) -> Bool {
        guard let gatewayIndex = observed.firstIndex(where: { $0.ipAddress == gatewayIP }),
              let gateway = saved.first(where: { $0.ipAddress == gatewayIP && matches(observed[gatewayIndex], $0, atSameAddress: true) })
        else { return false }
        var usedDevices: Set<UUID> = [gateway.deviceID]
        var others = 0
        for (index, seen) in observed.enumerated() where index != gatewayIndex {
            let match = saved.first { row in
                !usedDevices.contains(row.deviceID) && matches(seen, row, atSameAddress: row.ipAddress == seen.ipAddress)
            }
            guard let match else { continue }
            usedDevices.insert(match.deviceID)
            others += 1
        }
        return others >= othersNeeded
    }

    private static func matches(_ seen: Observation, _ row: SavedDevice, atSameAddress: Bool) -> Bool {
        if let mac = realMAC(seen.macAddress), mac == realMAC(row.macAddress) {
            return true
        }
        guard atSameAddress, let name = normalizedName(seen.name) else { return false }
        return name == normalizedName(row.name)
    }

    /// A globally administered MAC, normalised; nil for a private (locally administered) or missing one.
    static func realMAC(_ mac: String?) -> String? {
        guard let normalized = DeviceMatcher.normalizedMAC(mac), let first = UInt8(normalized.prefix(2), radix: 16),
              first & 0x02 == 0 else { return nil }
        return normalized
    }

    /// The name contract: lowercase and trim; drop a trailing "." and ".local"; keep a DNS name's first
    /// label; nil when empty or generic (`BonjourHostName.isGeneric`).
    public static func normalizedName(_ name: String?) -> String? {
        guard var label = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        while label.hasSuffix(".") {
            label.removeLast()
        }
        if label.hasSuffix(".local") {
            label.removeLast(".local".count)
        }
        label = String(label.split(separator: ".").first ?? "")
        guard !label.isEmpty, !BonjourHostName.isGeneric(label, maker: nil, model: nil) else { return nil }
        return label
    }
}
