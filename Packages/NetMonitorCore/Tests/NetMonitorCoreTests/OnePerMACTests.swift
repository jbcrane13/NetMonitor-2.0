import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 PR2 (v3.1 §5): several answering observations of one real MAC keep one, chosen the same
/// whatever the scan's order: the address of the row that already has that MAC, else the lowest
/// IPv4. An answering one always beats a cached one.
@Suite("One observation per MAC")
@MainActor
struct OnePerMACTests {
    func device(_ ip: String, mac: String? = "AA:BB:CC:00:00:01", cached: Bool = false) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: nil, vendor: nil, macAddress: mac, latency: 2, discoveredAt: Date(), source: .local, isCached: cached
        )
    }

    @Test("The lowest IPv4 wins between answering duplicates, in any order")
    func lowestAddressWins() {
        let scans = [[device("10.0.0.20"), device("10.0.0.9")], [device("10.0.0.9"), device("10.0.0.20")]]
        for scan in scans {
            #expect(PresenceMatch.onePerMAC(scan).map(\.ipAddress) == ["10.0.0.9"])
        }
    }

    @Test("The address of the row that already has the MAC wins, in any order")
    func knownRowWins() throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let row = LocalDevice(ipAddress: "10.0.0.20", macAddress: "aa:bb:cc:00:00:01")
        container.mainContext.insert(row)
        for scan in [[device("10.0.0.20"), device("10.0.0.9")], [device("10.0.0.9"), device("10.0.0.20")]] {
            #expect(PresenceMatch.onePerMAC(scan, known: [row]).map(\.ipAddress) == ["10.0.0.20"])
        }
    }

    @Test("An answering observation beats a cached one; observations without a MAC are all kept")
    func answeringBeatsCached() {
        let scan = [device("10.0.0.5", cached: true), device("10.0.0.50"), device("10.0.0.7", mac: nil), device("10.0.0.8", mac: nil)]
        #expect(PresenceMatch.onePerMAC(scan).map(\.ipAddress) == ["10.0.0.50", "10.0.0.7", "10.0.0.8"])
    }

    @Test("Only the scanned network's row counts: another network's row at an address doesn't")
    func knownRowsAreTheNetworks() throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let home = UUID(), office = UUID()
        let homeRow = LocalDevice(ipAddress: "10.0.0.20", macAddress: "AA:BB:CC:00:00:01", networkProfileID: home)
        let officeRow = LocalDevice(ipAddress: "10.0.0.35", macAddress: "AA:BB:CC:00:00:01", networkProfileID: office)
        container.mainContext.insert(homeRow)
        container.mainContext.insert(officeRow)
        let scan = [device("10.0.0.20"), device("10.0.0.35")]
        #expect(PresenceMatch.onePerMAC(scan, known: [officeRow]).map(\.ipAddress) == ["10.0.0.35"])
    }
}
