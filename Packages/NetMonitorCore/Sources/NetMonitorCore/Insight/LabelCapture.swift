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
/// does (#449), so no scan replaces them; so does the serial (#561), which before kept to a
/// `Serial:` notes line (`SerialNotesMigration` moves those). The MAC is written only to a device that
/// has none, and never when another device already has it (#442: one MAC, one device).
public enum LabelCapture {
    /// The other device that has a MAC: a saved row, or a device the latest scan saw that has
    /// no row yet.
    public enum MACOwner: Equatable, Sendable {
        case saved(UUID)
        case scanned(ipAddress: String)
    }

    public enum MACOutcome: Equatable, Sendable {
        /// No MAC to save.
        case none
        /// Text that isn't a MAC; Save waits until it is fixed or cleared.
        case invalid
        /// The device already has this MAC.
        case unchanged
        /// The device had no MAC and now has this one.
        case written
        /// The device has a different MAC, which is kept: the scan keys the device by it.
        case kept(existing: String)
        /// Another device has the MAC; it wasn't copied.
        case belongsTo(MACOwner)
    }

    static let serialPrefix = "Serial: "

    /// The other device with `mac` that the device match (`DeviceMatcher`) would give this
    /// MAC to: a saved row on `device`'s network or one with no network yet (adopted by the
    /// first network it's opened on), else a device in `scanned` on the same network at
    /// another address. `scanned` is the latest scan, so a device without a row still counts.
    public static func owner(
        of mac: String,
        besides device: LocalDevice,
        among rows: [LocalDevice],
        scanned: [DiscoveredDevice] = []
    ) -> MACOwner? {
        guard let mac = DeviceMatcher.normalizedMAC(mac) else { return nil }
        if let row = rows.first(where: {
            $0.id != device.id && ($0.networkProfileID == device.networkProfileID || $0.networkProfileID == nil)
                && DeviceMatcher.normalizedMAC($0.macAddress) == mac
        }) {
            return .saved(row.id)
        }
        return scanned.first {
            $0.networkProfileID == device.networkProfileID && $0.ipAddress != device.ipAddress
                && DeviceMatcher.normalizedMAC($0.macAddress) == mac
        }.map { .scanned(ipAddress: $0.ipAddress) }
    }

    /// Writes `values` to `device`; `rows` and `scanned` are for the duplicate-MAC check. An
    /// invalid MAC is not written (the review keeps Save off until it is fixed).
    @discardableResult
    public static func save(
        _ values: LabelValues,
        to device: LocalDevice,
        among rows: [LocalDevice],
        scanned: [DiscoveredDevice] = []
    ) -> MACOutcome {
        func confirmed(_ text: String) -> IdentityValue? {
            let text: String? = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return IdentityValue(text, source: .userConfirmed)
        }
        let identity = device.identity.merging(DeviceIdentity(
            maker: confirmed(values.maker), model: confirmed(values.model), serial: confirmed(values.serial)
        ))
        if identity != device.identity {
            device.identity = identity
        }
        let outcome = macOutcome(for: values.mac, on: device, among: rows, scanned: scanned)
        if outcome == .written, let mac = LabelTextScanner.mac(from: values.mac) {
            device.macAddress = mac
        }
        return outcome
    }

    /// What Save would do with `mac` on `device`, without writing anything, so the review
    /// sheet can say so first.
    public static func macOutcome(
        for mac: String,
        on device: LocalDevice,
        among rows: [LocalDevice],
        scanned: [DiscoveredDevice] = []
    ) -> MACOutcome {
        let text = mac.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .none }
        // Strict: six two-digit groups or 12 digits, so a typo like `…:1B:2` isn't read as `…:1B:02`.
        guard let mac = LabelTextScanner.mac(from: text) else { return .invalid }
        let existing = DeviceMatcher.normalizedMAC(device.macAddress)
        if existing == mac {
            return .unchanged
        }
        if let owner = owner(of: mac, besides: device, among: rows, scanned: scanned) {
            return .belongsTo(owner)
        }
        return existing.map { .kept(existing: $0) } ?? .written
    }
}
