import Testing
import Foundation
import NetworkScanKit
@testable import NetMonitorCore

/// The paired Mac's device list counts as devices answering now only while the Mac is connected and
/// the list is recent (#598); otherwise it adds cached sightings, which never count as answers.
@Suite("Companion sightings")
struct CompanionSightingsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let list = DeviceListPayload(devices: [
        DeviceInfo(ipAddress: "192.168.7.60", macAddress: "AA:BB:CC:00:00:60", hostname: "tv", vendor: nil, deviceType: "tv", isOnline: true),
        DeviceInfo(ipAddress: "192.168.7.61", macAddress: "", hostname: "gone", vendor: nil, deviceType: "unknown", isOnline: false),
        DeviceInfo(ipAddress: "10.0.0.9", macAddress: "", hostname: "elsewhere", vendor: nil, deviceType: "unknown", isOnline: true)
    ])

    func sightings(receivedAt: Date?, connected: Bool) -> (devices: [DiscoveredDevice], fresh: Bool) {
        DeviceDiscoveryService.companionSightings(
            list: list, receivedAt: receivedAt, macConnected: connected, now: now,
            includes: { $0.hasPrefix("192.168.7.") }, profileID: nil
        )
    }

    @Test func aRecentListFromAConnectedMacIsFresh() {
        let result = sightings(receivedAt: now.addingTimeInterval(-30), connected: true)
        #expect(result.fresh)
        // Only the online devices on the scanned network.
        #expect(result.devices.map(\.ipAddress) == ["192.168.7.60"])
    }

    @Test func aListFromADisconnectedMacIsStale() {
        #expect(!sightings(receivedAt: now.addingTimeInterval(-30), connected: false).fresh)
        // A dropped link clears the receive time.
        #expect(!sightings(receivedAt: nil, connected: true).fresh)
    }

    @Test func aListOlderThanTheBoundIsStale() {
        let old = now.addingTimeInterval(-DeviceDiscoveryService.companionListFreshness)
        #expect(!sightings(receivedAt: old, connected: true).fresh)
        #expect(DeviceDiscoveryService.companionListFreshness == 120)
    }

    /// Merged without confirming presence, a stale list's device is a cached sighting unless this
    /// phone found it too.
    @Test func aStaleSightingIsCachedUnlessThePhoneFoundTheDevice() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.7.70", hostname: "laptop", vendor: nil, macAddress: nil, latency: 3, discoveredAt: now, source: .local
        ))
        let stale = sightings(receivedAt: nil, connected: false)
        for device in stale.devices + [DiscoveredDevice(
            ipAddress: "192.168.7.70", hostname: nil, vendor: nil, macAddress: nil, latency: nil, discoveredAt: now, source: .macCompanion
        )] {
            await accumulator.upsert(device, confirmsPresence: stale.fresh)
        }
        let snapshot = await accumulator.snapshot()
        #expect(snapshot.first { $0.ipAddress == "192.168.7.60" }?.isCached == true)
        #expect(snapshot.first { $0.ipAddress == "192.168.7.70" }?.isCached == false)
    }
}
