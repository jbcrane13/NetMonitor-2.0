import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// #446: iOS and macOS rows show the same maker and model label for the same device.
@Suite("Device maker label")
@MainActor
struct DeviceMakerLabelTests {
    private let identity = DeviceIdentity(
        maker: IdentityValue("Ubiquiti", source: .unifi),
        model: IdentityValue("U7 Pro", source: .unifi)
    )

    @Test("A scanned device and a saved one with the same identity get the same label")
    func sameLabelOnBothPlatforms() {
        let scanned = DiscoveredDevice(
            ipAddress: "192.168.2.4", hostname: nil, vendor: nil, macAddress: "28:70:4E:00:00:04",
            latency: nil, discoveredAt: Date(), source: .local, identity: identity
        )
        let saved = LocalDevice(ipAddress: "192.168.2.4", macAddress: "28:70:4E:00:00:04")
        saved.identity = identity

        #expect(scanned.makerLabel == "Ubiquiti · U7 Pro")
        #expect(saved.makerLabel == scanned.makerLabel)
    }

    @Test("The model alone, and the private-address label, as on macOS")
    func otherLabels() {
        let modelOnly = DiscoveredDevice(
            ipAddress: "192.168.2.5", hostname: nil, vendor: nil, macAddress: nil, latency: nil,
            discoveredAt: Date(), source: .bonjour, identity: DeviceIdentity(model: IdentityValue("Mac16,11", source: .bonjour))
        )
        #expect(modelOnly.makerLabel == "Mac16,11")

        let privateMAC = LocalDevice(ipAddress: "192.168.2.6", macAddress: "AA:BB:CC:00:00:01")
        #expect(privateMAC.makerLabel == MACAddress.privateAddressLabel)
    }
}
