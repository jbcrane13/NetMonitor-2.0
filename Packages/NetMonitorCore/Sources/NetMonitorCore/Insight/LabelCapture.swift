import Foundation
import NetworkScanKit

/// The label fields as the user reviews and edits them before saving (#456).
public struct LabelValues: Sendable, Equatable {
    public var maker: String
    public var model: String
    public var serial: String
    public var mac: String

    public init(maker: String = "", model: String = "", serial: String = "", mac: String = "") {
        self.maker = maker
        self.model = model
        self.serial = serial
        self.mac = mac
    }

    public init(_ reading: LabelReading) {
        self.init(maker: reading.maker ?? "", model: reading.model ?? "", serial: reading.serial ?? "", mac: reading.mac ?? "")
    }
}

/// Saves what the user confirmed from a label photo (#456). The maker and model go through the
/// identity seam as ``IdentitySource/userConfirmed`` (ADR-022), the way accepting a suggestion
/// does (#449), so no scan replaces them. `LocalDevice` has no serial field, so the serial is
/// kept as a `Serial:` line in the notes. The MAC is written only to a device that has none,
/// and never when another device on the network already has it (#442: one MAC, one device).
public enum LabelCapture {
    public enum MACOutcome: Equatable, Sendable {
        /// No valid MAC to save.
        case none
        /// The device already has this MAC.
        case unchanged
        /// The device had no MAC and now has this one.
        case written
        /// The device has a different MAC, which is kept: the scan keys the device by it.
        case kept(existing: String)
        /// Another device on this network has the MAC; it wasn't copied.
        case belongsTo(UUID)
    }

    static let serialPrefix = "Serial: "

    /// The other device on `device`'s network whose MAC is `mac`, if any.
    public static func owner(of mac: String, besides device: LocalDevice, among rows: [LocalDevice]) -> LocalDevice? {
        guard let mac = DeviceMatcher.normalizedMAC(mac) else { return nil }
        return rows.first {
            $0.id != device.id && $0.networkProfileID == device.networkProfileID && DeviceMatcher.normalizedMAC($0.macAddress) == mac
        }
    }

    /// Writes `values` to `device`; `rows` are the saved devices, for the duplicate-MAC check.
    @discardableResult
    public static func save(_ values: LabelValues, to device: LocalDevice, among rows: [LocalDevice]) -> MACOutcome {
        func confirmed(_ text: String) -> IdentityValue? {
            let text: String? = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return IdentityValue(text, source: .userConfirmed)
        }
        let identity = device.identity.merging(DeviceIdentity(maker: confirmed(values.maker), model: confirmed(values.model)))
        if identity != device.identity {
            device.identity = identity
        }
        let serial = values.serial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serial.isEmpty {
            device.notes = notes(device.notes, serial: serial)
        }
        return saveMAC(values.mac, to: device, among: rows)
    }

    /// What Save would do with `mac` on `device`, without writing anything, so the review
    /// sheet can say so first.
    public static func macOutcome(for mac: String, on device: LocalDevice, among rows: [LocalDevice]) -> MACOutcome {
        guard let mac = DeviceMatcher.normalizedMAC(mac.trimmingCharacters(in: .whitespaces)) else { return .none }
        let existing = DeviceMatcher.normalizedMAC(device.macAddress)
        if existing == mac {
            return .unchanged
        }
        if let owner = owner(of: mac, besides: device, among: rows) {
            return .belongsTo(owner.id)
        }
        return existing.map { .kept(existing: $0) } ?? .written
    }

    private static func saveMAC(_ text: String, to device: LocalDevice, among rows: [LocalDevice]) -> MACOutcome {
        let outcome = macOutcome(for: text, on: device, among: rows)
        if outcome == .written, let mac = DeviceMatcher.normalizedMAC(text.trimmingCharacters(in: .whitespaces)) {
            device.macAddress = mac
        }
        return outcome
    }

    /// `notes` with its `Serial:` line set to `serial`.
    static func notes(_ notes: String?, serial: String) -> String {
        let line = serialPrefix + serial
        var lines = (notes ?? "").components(separatedBy: "\n")
        if let index = lines.firstIndex(where: { $0.hasPrefix(serialPrefix) }) {
            lines[index] = line
        } else if lines == [""] {
            lines = [line]
        } else {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
