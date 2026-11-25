import Foundation
import Network

/// The Mac's Bonjour TXT record for the companion service (#590): the protocol version (`pv`)
/// and the Mac's ID (`mac`). The phone reads it for its screen only ("Paired", "Needs an
/// update"); security never depends on it.
public enum CompanionServiceTXT {
    public static func record(macID: UUID) -> NWTXTRecord {
        var record = NWTXTRecord()
        record["pv"] = String(CompanionMessage.currentProtocolVersion)
        record["mac"] = macID.uuidString
        return record
    }

    /// The Mac's ID and protocol version; nil fields when absent, as from a Mac before v2.
    public static func read(_ record: NWTXTRecord) -> (macID: UUID?, protocolVersion: Int?) {
        (record["mac"].flatMap(UUID.init(uuidString:)), record["pv"].flatMap { Int($0) })
    }
}

/// Where the companion link lives (#590).
public enum CompanionLink {
    public static let defaultPort: UInt16 = 8849
    public static let serviceType = "_netmon._tcp"
}

extension Data {
    /// Lowercase hex, two digits per byte.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Bytes from hex with an even number of digits; nil otherwise.
    public init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
