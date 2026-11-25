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
