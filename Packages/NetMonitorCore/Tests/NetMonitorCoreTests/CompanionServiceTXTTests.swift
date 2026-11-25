import Foundation
import Network
import Testing
@testable import NetMonitorCore

@Suite("CompanionServiceTXT")
struct CompanionServiceTXTTests {
    @Test("What the Mac advertises, the phone reads back: its ID and protocol version 2")
    func roundTrip() {
        let macID = UUID()
        let read = CompanionServiceTXT.read(CompanionServiceTXT.record(macID: macID))
        #expect(read.macID == macID)
        #expect(read.protocolVersion == 2)
        #expect(DiscoveredMac(id: "x", name: "Mac", macID: read.macID, protocolVersion: read.protocolVersion).isCurrent)
    }

    @Test("A Mac before v2 advertises an empty record: no ID, no version, not current")
    func oldMac() {
        let read = CompanionServiceTXT.read(NWTXTRecord())
        #expect(read.macID == nil)
        #expect(read.protocolVersion == nil)
        #expect(!DiscoveredMac(id: "x", name: "Mac").isCurrent)
    }
}
