import Foundation

/// A device a phrase can name, read through the identity seam: the display name, type and maker
/// (`LocalDevice.displayName`, `deviceType`, `maker`).
public protocol DevicePhraseMatchable {
    var displayName: String { get }
    var deviceType: DeviceType { get }
    var maker: String? { get }
}

public enum DevicePhraseResolution<Device: Equatable & Sendable>: Equatable, Sendable {
    case one(Device)
    /// More than one device fits; the user picks.
    case several([Device])
    case none
}

/// Finds the device a phrase such as "the NAS" means (#451; the same rule as #450's alert rules).
/// The app does this, not the model: the model copies the user's words and never maps "NAS" to
/// "Synology DS920" itself.
///
/// A device whose name is the phrase (without "the", "my" …) wins. Otherwise a device fits when
/// every word of the phrase is a word of its name or maker, or names its type ("NAS" for storage).
/// Words are whole words, so "nas" never matches "Jonas".
public enum DevicePhraseResolver {
    public static func resolve<Device: DevicePhraseMatchable & Equatable & Sendable>(
        _ phrase: String,
        among devices: [Device]
    ) -> DevicePhraseResolution<Device> {
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

    static let fillerWords: Set<String> = ["the", "my", "our", "a", "an", "s", "device"]

    private static func significantWords(_ text: String) -> [String] {
        tokens(text).filter { !fillerWords.contains($0) }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
