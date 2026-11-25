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
            case .serial: return DeviceIdentity(serial: value)
            }
        }
        let merged = identity("current", current).merging(identity("newer", newer))
        switch field {
        case .maker: return merged.maker?.value
        case .model: return merged.model?.value
        case .friendlyName: return merged.friendlyName?.value
        case .serial: return merged.serial?.value
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
        #expect(DeviceIdentity(maker: IdentityValue("Wiz", source: .upnp)).resolvedMaker(macPrefixMaker: "Sonos, Inc.") == "Wiz")
        #expect(DeviceIdentity(maker: IdentityValue("Roku", source: .hostnameGuess)).resolvedMaker(macPrefixMaker: "Sonos, Inc.") == "Sonos, Inc.")
        #expect(DeviceIdentity(maker: IdentityValue("Samsung", source: nil)).resolvedMaker(macPrefixMaker: "Samsung Electronics Co.,Ltd")
            == "Samsung Electronics Co.,Ltd")
        #expect(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)).resolvedMaker(macPrefixMaker: nil) == "Meross")
        #expect(DeviceIdentity().resolvedMaker(macPrefixMaker: "") == nil)
    }

    @Test("A chip maker's MAC prefix loses to any other maker, even a guess")
    func chipMakerLosesToAGuess() {
        let guess = DeviceIdentity(maker: IdentityValue("Lutron", source: .hostnameGuess))
        #expect(guess.resolvedMaker(macPrefixMaker: "Texas Instruments") == "Lutron")
        #expect(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)).resolvedMaker(macPrefixMaker: "Espressif Inc.") == "Meross")
        // Still shown when nothing else names the device, and a device maker's own prefix still wins.
        #expect(DeviceIdentity().resolvedMaker(macPrefixMaker: "Texas Instruments") == "Texas Instruments")
        let guessed = DeviceIdentity(maker: IdentityValue("Apple TV", source: .hostnameGuess))
        #expect(guessed.resolvedMaker(macPrefixMaker: "Apple, Inc.") == "Apple, Inc.")
    }

    @Test("A guess may name the device when only a chip maker is known")
    func guessingIgnoresChipMakers() {
        #expect(DeviceIdentity().knownMakerForGuessing(macPrefixMaker: "Texas Instruments") == nil)
        #expect(DeviceIdentity().knownMakerForGuessing(macPrefixMaker: "Apple") == "Apple")
        #expect(DeviceIdentity.isChipMaker("ESPRESSIF INC."))
        #expect(DeviceIdentity.isChipMaker("Intel Corporate"))
        #expect(!DeviceIdentity.isChipMaker("Intelbras"))
        #expect(!DeviceIdentity.isChipMaker("Sonos, Inc."))
    }

    // MARK: - Model suggestions and user confirmation (#449)

    @Test("Rank table for a model suggestion and a user confirmation")
    func suggestionAndConfirmationRanks() {
        for field in [IdentitySource.Field.maker, .model, .friendlyName] {
            #expect(IdentitySource.modelSuggestion.rank(for: field) == -1)
        }
        #expect(IdentitySource.userConfirmed.rank(for: .maker) == 10)
        #expect(IdentitySource.userConfirmed.rank(for: .model) == 10)
        #expect(IdentitySource.userConfirmed.rank(for: .friendlyName) == -1)
    }

    @Test("A suggestion loses to every source and to a sourceless value, in both merge orders", arguments: [
        IdentitySource.Field.maker, .model, .friendlyName
    ])
    func suggestionLosesToEverything(field: IdentitySource.Field) {
        let others: [IdentitySource?] = IdentitySource.allCases.filter { $0 != .modelSuggestion } + [nil]
        for other in others {
            // userConfirmed never names a device, so on a friendly name it ties with a suggestion.
            if field == .friendlyName, other == .userConfirmed {
                continue
            }
            #expect(merge(field, .modelSuggestion, other) == "newer", "\(field) \(String(describing: other))")
            #expect(merge(field, other, .modelSuggestion) == "current", "\(field) \(String(describing: other))")
        }
    }

    @Test("A suggestion fills an empty field and never wins a friendly name over another source")
    func suggestionFillsOnlyEmpty() {
        let suggested = DeviceIdentity(maker: IdentityValue("Lutron", source: .modelSuggestion))
        #expect(DeviceIdentity().merging(suggested) == suggested)
        #expect(merge(.friendlyName, .upnp, .modelSuggestion) == "current")
        #expect(merge(.friendlyName, nil, .modelSuggestion) == "current")
    }

    @Test("A user-confirmed value beats a Bonjour model and a UPnP maker", arguments: [
        (IdentitySource.Field.model, IdentitySource.bonjour),
        (.maker, .upnp),
        (.maker, .unifi),
        (.model, .unifi)
    ])
    func confirmedBeatsAnnouncements(field: IdentitySource.Field, announced: IdentitySource) {
        #expect(merge(field, .userConfirmed, announced) == "current")
        #expect(merge(field, announced, .userConfirmed) == "newer")
    }

    @Test("A suggested maker beats a chip maker's MAC prefix but not a device maker's")
    func suggestionAgainstMACPrefix() {
        let suggested = DeviceIdentity(maker: IdentityValue("Lutron", source: .modelSuggestion))
        #expect(suggested.resolvedMaker(macPrefixMaker: "Texas Instruments") == "Lutron")
        #expect(suggested.winningMaker(macPrefixMaker: "Texas Instruments")?.source == .modelSuggestion)
        #expect(suggested.resolvedMaker(macPrefixMaker: "Apple, Inc.") == "Apple, Inc.")
        #expect(suggested.winningMaker(macPrefixMaker: "Apple, Inc.") == IdentityValue("Apple, Inc.", source: .macPrefix))
        #expect(suggested.winningMaker(macPrefixMaker: nil)?.source == .modelSuggestion)
        #expect(DeviceIdentity().winningMaker(macPrefixMaker: nil) == nil)
    }

    @Test("A guess ignores a suggested maker")
    func guessingIgnoresSuggestions() {
        let suggested = DeviceIdentity(maker: IdentityValue("Lutron", source: .modelSuggestion))
        #expect(suggested.knownMakerForGuessing(macPrefixMaker: nil) == nil)
        #expect(suggested.knownMakerForGuessing(macPrefixMaker: "Texas Instruments") == nil)
        #expect(suggested.knownMakerForGuessing(macPrefixMaker: "Apple") == "Apple")
        let guessed = DeviceIdentity(maker: IdentityValue("Lutron", source: .hostnameGuess))
        #expect(guessed.knownMakerForGuessing(macPrefixMaker: "Texas Instruments") == "Lutron")
    }

    @Test("The hostname step fills a model over a suggested one")
    func hostnameStepIgnoresSuggestions() {
        let device = DiscoveredDevice(
            ipAddress: "192.168.2.71", hostname: "unifi-pro-max-16-switch.lan", vendor: nil, macAddress: nil,
            latency: nil, discoveredAt: Date(), source: .local,
            identity: DeviceIdentity(
                maker: IdentityValue("Netgear", source: .modelSuggestion),
                model: IdentityValue("Switch", source: .modelSuggestion)
            )
        )
        let update = HostnameIdentityPhase.update(for: device)
        #expect(update?.identity.maker == IdentityValue("Ubiquiti", source: .hostnameGuess))
        #expect(update?.identity.model == IdentityValue("UniFi Pro Max 16 Switch", source: .hostnameGuess))
        #expect(device.withIdentity(update?.identity ?? DeviceIdentity()).modelName == "UniFi Pro Max 16 Switch")
    }

    @Test("withoutSuggestions drops only suggested values")
    func withoutSuggestions() {
        let identity = DeviceIdentity(
            maker: IdentityValue("Lutron", source: .modelSuggestion),
            model: IdentityValue("Caseta", source: .userConfirmed),
            friendlyName: IdentityValue("Bridge", source: .upnp)
        )
        #expect(identity.withoutSuggestions == DeviceIdentity(
            model: IdentityValue("Caseta", source: .userConfirmed),
            friendlyName: IdentityValue("Bridge", source: .upnp)
        ))
        let unsourced = DeviceIdentity(model: IdentityValue("Q80", source: nil))
        #expect(unsourced.withoutSuggestions == unsourced)
    }

    @Test("The hostname step names a Lutron bridge whose MAC prefix is Texas Instruments")
    func hostnameStepNamesChipDevices() {
        let bridge = DiscoveredDevice(
            ipAddress: "192.168.2.70", hostname: "lutron-02e1f4a1.lan", vendor: "Texas Instruments",
            macAddress: nil, latency: nil, discoveredAt: Date(), source: .local
        )
        let update = HostnameIdentityPhase.update(for: bridge)
        #expect(update?.identity.maker == IdentityValue("Lutron", source: .hostnameGuess))
        #expect(bridge.withIdentity(update?.identity ?? DeviceIdentity()).maker == "Lutron")
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

    @Test("Serial (#561): user-confirmed > UPnP > no source; a suggestion never wins", arguments: [
        (IdentitySource?.some(.userConfirmed), IdentitySource?.some(.upnp), "current"),
        (.upnp, .userConfirmed, "newer"),
        (nil, .upnp, "newer"),
        (.upnp, nil, "current"),
        (nil, .modelSuggestion, "current")
    ])
    func serialRanks(current: IdentitySource?, newer: IdentitySource?, winner: String) {
        #expect(merge(.serial, current, newer) == winner)
    }

    @Test("A serial survives withoutSuggestions unless it is a suggestion")
    func serialWithoutSuggestions() {
        let confirmed = DeviceIdentity(serial: IdentityValue("C02", source: .userConfirmed))
        let suggested = DeviceIdentity(serial: IdentityValue("C02", source: .modelSuggestion))
        #expect(confirmed.withoutSuggestions.serial?.value == "C02")
        #expect(suggested.withoutSuggestions.serial == nil)
    }
}
