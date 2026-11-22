import Testing
import Foundation
import NetworkScanKit
@testable import NetMonitorCore

/// Tests for `ScanDisplayPhase(phaseID:)`, the mapping used by `DeviceDiscoveryService`
/// to translate a NetworkScanKit `ScanPhaseID` into the UI-facing display phase.
struct DeviceDiscoveryServiceTests {

    // MARK: - ScanDisplayPhase(phaseID:)

    @Test("every built-in ScanPhaseID maps to a non-nil ScanDisplayPhase")
    func everyBuiltInScanPhaseIDMapsToNonNilScanDisplayPhase() {
        let builtInPhaseIDs: [ScanPhaseID] = [.arp, .bonjour, .tcpProbe, .ssdp, .icmpLatency, .reverseDNS]
        for phaseID in builtInPhaseIDs {
            #expect(ScanDisplayPhase(phaseID: phaseID) != nil, "\(phaseID.rawValue) should map to a display phase")
        }
    }

    @Test("an unknown ScanPhaseID maps to a nil ScanDisplayPhase")
    func unknownScanPhaseIDMapsToNilScanDisplayPhase() {
        #expect(ScanDisplayPhase(phaseID: "custom-platform-phase") == nil)
    }

    // MARK: - withProfile (#378)

    private func makeDevice(isCached: Bool) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: "192.168.1.20",
            hostname: "printer.local",
            vendor: "Acme",
            macAddress: "AA:BB:CC:DD:EE:FF",
            latency: nil,
            discoveredAt: Date(timeIntervalSince1970: 1000),
            source: .local,
            isCached: isCached
        )
    }

    @Test("withProfile keeps isCached and sets the profile ID")
    func withProfileKeepsCached() {
        let profileID = UUID()
        let device = makeDevice(isCached: true)

        let copy = DeviceDiscoveryService.withProfile(device, profileID: profileID)

        #expect(copy.isCached)
        #expect(copy.networkProfileID == profileID)
        #expect(copy.id == device.id)
        #expect(copy.ipAddress == device.ipAddress)
        #expect(copy.macAddress == device.macAddress)
    }

    @Test("withProfile keeps the identity and its sources (#387, ADR-022)")
    func withProfileKeepsDescription() {
        let identity = DeviceIdentity(
            maker: IdentityValue("Samsung Electronics", source: .upnp),
            model: IdentityValue("Q80", source: .upnp),
            friendlyName: IdentityValue("Living Room TV", source: .upnp)
        )
        let device = DiscoveredDevice(
            ipAddress: "192.168.1.20", hostname: nil, vendor: nil, macAddress: nil,
            latency: nil, discoveredAt: Date(), source: .ssdp, identity: identity
        )

        let copy = DeviceDiscoveryService.withProfile(device, profileID: UUID())

        #expect(copy.identity == identity)
        #expect(copy.displayName == "Living Room TV")
    }

    @Test("withProfile keeps an answered device answered")
    func withProfileKeepsAnswered() {
        let copy = DeviceDiscoveryService.withProfile(makeDevice(isCached: false), profileID: nil)
        #expect(!copy.isCached)
    }

    @Test("an empty scan after an online device keeps it, marked cached (#378)")
    func emptyScanMarksPreviousDevicesCached() {
        let previous = [makeDevice(isCached: false)]

        let result = DeviceDiscoveryService.finalDevices(scanned: [], previous: previous)

        #expect(result.count == 1)
        #expect(result.first?.isCached == true)
        #expect(result.first?.ipAddress == previous.first?.ipAddress)
    }

    @Test("a non-empty scan replaces the previous devices")
    func nonEmptyScanReplacesPrevious() {
        let scanned = [makeDevice(isCached: false)]

        let result = DeviceDiscoveryService.finalDevices(scanned: scanned, previous: [makeDevice(isCached: false), makeDevice(isCached: false)])

        #expect(result.map(\.id) == scanned.map(\.id))
        #expect(result.first?.isCached == false)
    }

    @Test("mid-scan snapshots (keepCached: false) never show a device as cached")
    func withProfileMidScanClearsCached() {
        let copy = DeviceDiscoveryService.withProfile(makeDevice(isCached: true), profileID: nil, keepCached: false)
        #expect(!copy.isCached)
    }
}
