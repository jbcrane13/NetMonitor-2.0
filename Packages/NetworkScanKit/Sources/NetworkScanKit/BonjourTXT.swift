import Foundation

/// Reads Bonjour TXT records: the raw DNS-SD wire format, and the model keys that
/// device services publish (#386).
public enum BonjourTXT {

    /// TXT keys that carry a hardware model, by service type.
    /// - `_device-info._tcp` `model=MacBookPro18,1` (Apple devices)
    /// - `_airplay._tcp` `model=AppleTV11,1`, `_raop._tcp` `am=AudioAccessory5,1`
    /// - `_googlecast._tcp` `md=Chromecast`
    static let modelKeys: [String: String] = [
        "_device-info._tcp": "model",
        "_airplay._tcp": "model",
        "_raop._tcp": "am",
        "_googlecast._tcp": "md"
    ]

    /// The model a service's TXT record names, or nil.
    public static func model(serviceType: String, txt: [String: String]) -> String? {
        guard let key = modelKeys[normalizedType(serviceType)],
              let value = txt[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// The maker a device's Bonjour data proves, or nil (#426). A TXT `manufacturer=` key
    /// wins (Sonos publishes `manufacturer=Sonos` on `_airplay._tcp`); otherwise an Apple
    /// hardware identifier (`Mac16,11`, `AppleTV14,1`, `AudioAccessory1,1`) means Apple.
    /// The service type alone proves nothing: many non-Apple devices speak AirPlay.
    public static func vendor(txt: [String: String], model: String?) -> String? {
        if let maker = txt["manufacturer"]?.trimmingCharacters(in: .whitespacesAndNewlines), !maker.isEmpty {
            return maker
        }
        if let model, isAppleModelIdentifier(model) {
            return "Apple"
        }
        return nil
    }

    /// True for an Apple hardware model identifier: a product family then `major,minor`.
    static func isAppleModelIdentifier(_ model: String) -> Bool {
        let families = #/(Mac|MacBook|MacBookAir|MacBookPro|Macmini|MacPro|iMac|iMacPro|iPhone|iPad|iPod|AppleTV|AudioAccessory|Watch|RealityDevice)\d+,\d+/#
        return model.trimmingCharacters(in: .whitespaces).wholeMatch(of: families) != nil
    }

    /// Parses DNS-SD TXT wire data (RFC 6763 §6): a run of length-prefixed `key=value`
    /// strings. Keys are lowercased; a key without `=` maps to "". The first occurrence of
    /// a key wins; malformed trailing bytes are ignored.
    public static func parse(_ bytes: some Collection<UInt8>) -> [String: String] {
        let data = Array(bytes)
        var result: [String: String] = [:]
        var index = 0
        while index < data.count {
            let length = Int(data[index])
            index += 1
            guard length > 0 else { continue }
            guard index + length <= data.count else { break }
            let entry = data[index..<(index + length)]
            index += length
            let keyBytes = entry.prefix { $0 != UInt8(ascii: "=") }
            guard !keyBytes.isEmpty,
                  let key = String(bytes: keyBytes, encoding: .utf8)?.lowercased(),
                  result[key] == nil else {
                continue
            }
            let valueBytes = entry.dropFirst(keyBytes.count + 1)
            result[key] = String(bytes: valueBytes, encoding: .utf8) ?? ""
        }
        return result
    }

    /// "_airplay._tcp." / "_AirPlay._tcp.local." → "_airplay._tcp".
    static func normalizedType(_ type: String) -> String {
        let parts = type.lowercased().split(separator: ".")
        return parts.prefix(2).joined(separator: ".")
    }
}
