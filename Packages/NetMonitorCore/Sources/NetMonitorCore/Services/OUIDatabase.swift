import Foundation

/// The offline maker list built from the IEEE MA-L registry (`Resources/oui.tsv`, made by
/// `scripts/generate-oui-resource.py`). Loaded once, on first use (#384).
enum OUIDatabase {

    /// Organisation names keyed by the 24-bit OUI prefix.
    static let shared: [UInt32: String] = {
        guard let url = Bundle.module.url(forResource: "oui", withExtension: "tsv"),
              let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return parse(data)
    }()

    /// Parses "XXXXXX<TAB>Organization" lines; `#` comment lines and malformed lines are
    /// skipped.
    static func parse(_ data: Data) -> [UInt32: String] {
        guard let text = String(bytes: data, encoding: .utf8) else { return [:] }
        var vendors: [UInt32: String] = [:]
        vendors.reserveCapacity(41000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix("#"), let tab = line.firstIndex(of: "\t") else { continue }
            let prefix = line[..<tab]
            let name = line[line.index(after: tab)...]
            guard prefix.count == 6, !name.isEmpty, let key = UInt32(prefix, radix: 16) else { continue }
            vendors[key] = String(name)
        }
        return vendors
    }

    /// The organisation for a six-hex-digit OUI prefix (any case), or nil.
    static func vendor(forPrefix prefix: String) -> String? {
        guard prefix.count == 6, prefix.allSatisfy(\.isHexDigit), let key = UInt32(prefix, radix: 16) else {
            return nil
        }
        return shared[key]
    }
}
