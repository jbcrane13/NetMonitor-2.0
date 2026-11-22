import Foundation

/// Where a device's maker, model or friendly name came from (ADR-022). Each field ranks the
/// sources differently; see ``rank(for:)``.
public enum IdentitySource: String, Codable, Sendable, CaseIterable {
    /// A Bonjour TXT record (#386).
    case bonjour
    /// A UniFi discovery reply or the UniFi controller's client list (#439, #458).
    case unifi
    /// The device's UPnP description (#387).
    case upnp
    /// The maker registered for the MAC's prefix: the network chip's maker.
    case macPrefix
    /// A guess from the device's names (#439).
    case hostnameGuess

    public enum Field: Sendable {
        case maker, model, friendlyName
    }

    /// Higher wins. A value without a source (saved before sources were stored) ranks 0,
    /// below every source.
    ///
    /// - Model: Bonjour TXT > UniFi > UPnP > hostname guess.
    /// - Maker: the device's own announcement (UPnP, UniFi, Bonjour) > MAC-prefix maker >
    ///   hostname guess. The MAC prefix names whoever made the network chip.
    /// - Friendly name: UniFi > UPnP.
    public func rank(for field: Field) -> Int {
        switch (field, self) {
        case (.model, .bonjour): 4
        case (.model, .unifi): 3
        case (.model, .upnp): 2
        case (.maker, .bonjour), (.maker, .unifi), (.maker, .upnp): 3
        case (.maker, .macPrefix): 2
        case (.friendlyName, .unifi): 2
        default: 1
        }
    }
}

/// One identity value and the source that produced it.
public struct IdentityValue: Equatable, Codable, Sendable {
    public var value: String
    /// Nil for a value saved before sources were stored; it ranks below every source.
    public var source: IdentitySource?

    public init(_ value: String, source: IdentitySource?) {
        self.value = value
        self.source = source
    }

    /// A value, or nil when `value` is nil or empty.
    public init?(_ value: String?, source: IdentitySource?) {
        guard let value, !value.isEmpty else { return nil }
        self.init(value, source: source)
    }

    func rank(for field: IdentitySource.Field) -> Int {
        source?.rank(for: field) ?? 0
    }
}

/// A device's maker, model and friendly name with their sources (ADR-022). Every merge
/// (inside a scan, across scans, into a saved device) goes through ``merging(_:)``.
///
/// `maker` is the maker the device announced or a guess; the MAC-prefix maker is kept apart
/// (`vendor`) and compared with it by ``resolvedMaker(macPrefixMaker:)``.
public struct DeviceIdentity: Equatable, Sendable {
    public var maker: IdentityValue?
    public var model: IdentityValue?
    public var friendlyName: IdentityValue?

    public init(maker: IdentityValue? = nil, model: IdentityValue? = nil, friendlyName: IdentityValue? = nil) {
        self.maker = maker
        self.model = model
        self.friendlyName = friendlyName
    }

    /// Each field takes `newer`'s value when it ranks at least as high as the current one,
    /// so on equal rank the newer value wins.
    public func merging(_ newer: DeviceIdentity) -> DeviceIdentity {
        DeviceIdentity(
            maker: Self.winner(maker, newer.maker, .maker),
            model: Self.winner(model, newer.model, .model),
            friendlyName: Self.winner(friendlyName, newer.friendlyName, .friendlyName)
        )
    }

    /// The maker to show: ``maker`` or the MAC-prefix maker, whichever ranks higher.
    public func resolvedMaker(macPrefixMaker: String?) -> String? {
        Self.winner(IdentityValue(macPrefixMaker, source: .macPrefix), maker, .maker)?.value
    }

    private static func winner(_ current: IdentityValue?, _ newer: IdentityValue?, _ field: IdentitySource.Field) -> IdentityValue? {
        guard let newer else { return current }
        guard let current else { return newer }
        return newer.rank(for: field) >= current.rank(for: field) ? newer : current
    }
}
