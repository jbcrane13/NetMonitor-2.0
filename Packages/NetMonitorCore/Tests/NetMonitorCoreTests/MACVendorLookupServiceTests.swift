import Testing
@testable import NetMonitorCore

@Suite("MACVendorLookupService")
struct MACVendorLookupServiceTests {

    @Test("lookup resolves known Apple OUI from colon-separated MAC")
    func lookupKnownApplePrefix() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:03:93:AA:BB:CC")
        #expect(vendor == "Apple")
    }

    @Test("lookup normalizes dashed/lowercase MAC addresses")
    func lookupNormalizesDashSeparatedLowercase() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00-00-f0-aa-bb-cc")
        #expect(vendor == "Samsung")
    }

    @Test("lookup normalizes MAC addresses without separators")
    func lookupNormalizesSeparatorFreeFormat() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "000393112233")
        #expect(vendor == "Apple")
    }

    @Test("lookup returns nil for too-short MAC input")
    func lookupReturnsNilForShortInput() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "AA:BB")
        #expect(vendor == nil)
    }

    @Test("lookup returns nil for unknown prefix")
    func lookupReturnsNilForUnknownPrefix() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("enhanced lookup returns nil immediately for invalid short input")
    func enhancedLookupReturnsNilForShortInput() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookupVendorEnhanced(macAddress: "AB")
        #expect(vendor == nil)
    }

    // MARK: - Valid MAC to vendor name (parameterized)

    @Test("Known vendors resolved correctly from local database",
          arguments: [
            ("00:03:93:11:22:33", "Apple"),
            ("00:00:F0:AA:BB:CC", "Samsung"),
            ("00:1A:11:22:33:44", "Google"),
            ("00:FC:8B:11:22:33", "Amazon"),
            ("00:03:FF:11:22:33", "Microsoft"),
            ("00:02:B3:11:22:33", "Intel"),
            ("00:27:19:11:22:33", "TP-Link"),
            ("00:09:5B:11:22:33", "Netgear"),
            ("00:00:0C:11:22:33", "Cisco"),
            ("B8:27:EB:11:22:33", "Raspberry Pi"),
            ("00:0E:58:11:22:33", "Sonos"),
          ])
    func knownVendorsResolved(macAddress: String, expectedVendor: String) async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: macAddress)
        #expect(vendor == expectedVendor, "Expected \(expectedVendor) for MAC \(macAddress)")
    }

    // MARK: - Unknown MAC returns nil

    @Test("Completely unknown OUI prefix returns nil")
    func unknownOUIReturnsNil() async {
        let service = MACVendorLookupService()
        // Fabricated OUI unlikely to be in the database
        let vendor = await service.lookup(macAddress: "FF:FE:FD:01:02:03")
        #expect(vendor == nil)
    }

    @Test("All-zero MAC returns nil (no vendor mapped)")
    func allZeroMACReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:00:00:00:00:00")
        #expect(vendor == nil)
    }

    // MARK: - Malformed MAC address handling

    @Test("Empty string returns nil")
    func emptyStringReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "")
        #expect(vendor == nil)
    }

    @Test("Single character returns nil")
    func singleCharReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "A")
        #expect(vendor == nil)
    }

    @Test("Five hex chars (too short for OUI) returns nil")
    func fiveHexCharsReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "AA:BB:C")
        #expect(vendor == nil)
    }

    @Test("MAC with non-hex characters returns nil for lookup")
    func nonHexCharactersReturnsNil() async {
        let service = MACVendorLookupService()
        // 'GG' is not valid hex, but normalization just strips separators
        // and tries to match — the key is it doesn't crash
        let vendor = await service.lookup(macAddress: "GG:HH:II:JJ:KK:LL")
        #expect(vendor == nil)
    }

    // MARK: - OUI prefix matching logic

    @Test("OUI matching uses first 3 bytes (8 chars with colons)")
    func ouiMatchesFirstThreeBytes() async {
        let service = MACVendorLookupService()
        // Apple OUI 00:03:93 — last 3 bytes should not matter
        let vendor1 = await service.lookup(macAddress: "00:03:93:00:00:00")
        let vendor2 = await service.lookup(macAddress: "00:03:93:FF:FF:FF")
        #expect(vendor1 == "Apple")
        #expect(vendor2 == "Apple")
        #expect(vendor1 == vendor2)
    }

    @Test("OUI matching is case-insensitive")
    func ouiMatchingCaseInsensitive() async {
        let service = MACVendorLookupService()
        let upper = await service.lookup(macAddress: "00:03:93:AA:BB:CC")
        let lower = await service.lookup(macAddress: "00:03:93:aa:bb:cc")
        let mixed = await service.lookup(macAddress: "00:03:93:Aa:Bb:Cc")
        #expect(upper == "Apple")
        #expect(lower == "Apple")
        #expect(mixed == "Apple")
    }

    @Test("OUI matching works with dash separators")
    func ouiMatchingDashSeparators() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "B8-27-EB-11-22-33")
        #expect(vendor == "Raspberry Pi")
    }

    @Test("OUI matching works without separators")
    func ouiMatchingNoSeparators() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "B827EB112233")
        #expect(vendor == "Raspberry Pi")
    }
}
