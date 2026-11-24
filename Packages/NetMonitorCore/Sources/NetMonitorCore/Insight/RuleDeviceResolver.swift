import Foundation

/// A device a plain-English rule can name, read through the identity seam (`LocalDevice.id`,
/// `displayName`, `deviceType`, maker) (#450).
public struct RuleDevice: Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var displayName: String
    public var deviceType: DeviceType
    public var maker: String?
    public var ipAddress: String

    public init(id: UUID, displayName: String, deviceType: DeviceType, maker: String?, ipAddress: String) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
        self.maker = maker
        self.ipAddress = ipAddress
    }

    /// A saved device as rules see it: its stable identity and the identity seam's name, type and
    /// maker. The maker leaves out model suggestions, as alert rules do (#449).
    public init(_ device: LocalDevice) {
        self.init(
            id: device.id,
            displayName: device.displayName,
            deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions,
            ipAddress: device.ipAddress
        )
    }
}

public enum RuleDeviceResolution: Sendable, Equatable {
    case one(RuleDevice)
    /// More than one device fits; the user picks.
    case several([RuleDevice])
    case none
}

/// Finds the device a phrase such as "the NAS" means. The app does this, not the model: the
/// model copies the user's words and never maps "NAS" to "Synology DS920" itself.
///
/// A device whose name is the phrase (without "the", "my" …) wins. Otherwise a device fits when
/// every word of the phrase is a word of its name or maker, or names its type ("NAS" for
/// storage). Words are whole words, so "nas" never matches "Jonas".
public enum RuleDeviceResolver {
    public static func resolve(_ phrase: String, among devices: [RuleDevice]) -> RuleDeviceResolution {
        let words = significantWords(phrase)
        guard !words.isEmpty else { return .none }
        let exact = devices.filter { significantWords($0.displayName) == words }
        if exact.count == 1, let device = exact.first {
            return .one(device)
        }
        let fits = devices.filter { device in
            let own = Set(tokens(device.displayName) + tokens(device.maker ?? ""))
            let typeWords = typeWords[device.deviceType] ?? []
            return words.allSatisfy { own.contains($0) || typeWords.contains($0) }
        }
        switch fits.count {
        case 0: return .none
        case 1: return .one(fits[0])
        default: return .several(fits)
        }
    }

    /// Words that name each device type.
    static let typeWords: [DeviceType: Set<String>] = [
        .storage: ["nas", "storage", "drive", "disk"],
        .printer: ["printer"],
        .camera: ["camera", "cam", "webcam", "doorbell"],
        .tv: ["tv", "television", "appletv"],
        .router: ["router", "gateway", "modem"],
        .phone: ["phone", "iphone", "android"],
        .laptop: ["laptop", "macbook", "notebook"],
        .computer: ["computer", "desktop", "pc", "imac"],
        .speaker: ["speaker", "homepod"],
        .tablet: ["tablet", "ipad"],
        .gaming: ["console", "xbox", "playstation"],
        .iot: ["thermostat", "plug", "sensor", "bulb"]
    ]

    private static let fillerWords: Set<String> = ["the", "my", "our", "a", "an", "s", "device"]

    private static func significantWords(_ text: String) -> [String] {
        tokens(text).filter { !fillerWords.contains($0) }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
