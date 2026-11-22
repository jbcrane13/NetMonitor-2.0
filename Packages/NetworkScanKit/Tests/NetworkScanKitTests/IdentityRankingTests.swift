import Foundation
import Testing
@testable import NetworkScanKit

/// ADR-022: ranked identity sources (#462).
@Suite("Identity ranking")
struct IdentityRankingTests {

    private func merge(_ field: IdentitySource.Field, _ current: IdentitySource?, _ newer: IdentitySource?) -> String? {
        func identity(_ value: String, _ source: IdentitySource?) -> DeviceIdentity {
            let value = IdentityValue(value, source: source)
            switch field {
            case .maker: return DeviceIdentity(maker: value)
            case .model: return DeviceIdentity(model: value)
            case .friendlyName: return DeviceIdentity(friendlyName: value)
            }
        }
        let merged = identity("current", current).merging(identity("newer", newer))
        switch field {
        case .maker: return merged.maker?.value
        case .model: return merged.model?.value
        case .friendlyName: return merged.friendlyName?.value
        }
    }

    @Test("Model: Bonjour > UniFi > UPnP > hostname guess > no source", arguments: [
        (IdentitySource?.some(.bonjour), IdentitySource?.some(.unifi), "current"),
        (.unifi, .bonjour, "newer"),
        (.unifi, .upnp, "current"),
        (.upnp, .unifi, "newer"),
        (.upnp, .hostnameGuess, "current"),
        (.hostnameGuess, .upnp, "newer"),
        (nil, .hostnameGuess, "newer"),
        (.hostnameGuess, nil, "current")
    ])
    func modelRanks(current: IdentitySource?, newer: IdentitySource?, winner: String) {
        #expect(merge(.model, current, newer) == winner)
    }

    @Test("Maker: the device's announcement > MAC prefix > hostname guess > no source", arguments: [
        (IdentitySource?.some(.upnp), IdentitySource?.some(.macPrefix), "current"),
        (.macPrefix, .bonjour, "newer"),
        (.macPrefix, .hostnameGuess, "current"),
        (.hostnameGuess, .macPrefix, "newer"),
        (nil, .hostnameGuess, "newer")
    ])
    func makerRanks(current: IdentitySource?, newer: IdentitySource?, winner: String) {
        #expect(merge(.maker, current, newer) == winner)
    }

    @Test("Friendly name: UniFi > UPnP", arguments: [
        (IdentitySource?.some(.unifi), IdentitySource?.some(.upnp), "current"),
        (.upnp, .unifi, "newer")
    ])
    func friendlyNameRanks(current: IdentitySource?, newer: IdentitySource?, winner: String) {
        #expect(merge(.friendlyName, current, newer) == winner)
    }

    @Test("On equal rank the newer value wins", arguments: [
        (IdentitySource.Field.model, IdentitySource.bonjour, IdentitySource.bonjour),
        (.maker, .upnp, .unifi),
        (.maker, .bonjour, .upnp),
        (.friendlyName, .upnp, .upnp)
    ])
    func equalRankNewerWins(field: IdentitySource.Field, current: IdentitySource, newer: IdentitySource) {
        #expect(merge(field, current, newer) == "newer")
    }

    @Test("A missing value never replaces one")
    func missingKeeps() {
        let current = DeviceIdentity(model: IdentityValue("Q80", source: nil))
        #expect(current.merging(DeviceIdentity()) == current)
    }

    @Test("The shown maker: an announcement beats the MAC prefix, which beats a guess or an unsourced value")
    func resolvedMaker() {
        #expect(DeviceIdentity(maker: IdentityValue("Wiz", source: .upnp)).resolvedMaker(macPrefixMaker: "Espressif") == "Wiz")
        #expect(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)).resolvedMaker(macPrefixMaker: "Espressif") == "Espressif")
        #expect(DeviceIdentity(maker: IdentityValue("Samsung", source: nil)).resolvedMaker(macPrefixMaker: "Samsung Electronics Co.,Ltd")
            == "Samsung Electronics Co.,Ltd")
        #expect(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)).resolvedMaker(macPrefixMaker: nil) == "Meross")
        #expect(DeviceIdentity().resolvedMaker(macPrefixMaker: "") == nil)
    }

    @Test("Within a scan, a UPnP model after a Bonjour one doesn't replace it; a guess never does")
    func accumulatorRanks() async {
        func report(_ source: IdentitySource, model: String) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: "192.0.2.9", hostname: nil, vendor: nil, macAddress: nil, latency: nil,
                discoveredAt: Date(), source: .local, identity: DeviceIdentity(model: IdentityValue(model, source: source))
            )
        }
        let accumulator = ScanAccumulator()
        await accumulator.upsert(report(.hostnameGuess, model: "Apple TV"))
        await accumulator.upsert(report(.bonjour, model: "AppleTV14,1"))
        await accumulator.upsert(report(.upnp, model: "Apple TV 4K"))
        await accumulator.upsert(report(.hostnameGuess, model: "TV"))
        #expect(await accumulator.snapshot().first?.identity.model == IdentityValue("AppleTV14,1", source: .bonjour))
    }
}
