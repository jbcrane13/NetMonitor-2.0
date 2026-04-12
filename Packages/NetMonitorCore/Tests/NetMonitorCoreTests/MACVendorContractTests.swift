import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for MACVendorLookupService.
///
/// INTEGRATION GAP: MACVendorLookupService.lookupVendorOnline() uses
/// URLSession.shared internally rather than an injected session. This prevents
/// MockURLProtocol-based contract testing of the online API lookup path.
/// The `lookup()` method (local OUI database) is fully testable.
///
/// Resolution path: add `init(session: URLSession)` to MACVendorLookupService
/// to enable full contract testing with MockURLProtocol fixture responses.
struct MACVendorContractTests {

    // MARK: - Local OUI Database Lookup (the testable code path)

    @Test("Known Apple OUI resolves to 'Apple' via local database")
    func knownAppleOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:03:93:AA:BB:CC")
        #expect(vendor == "Apple")
    }

    @Test("Known Samsung OUI resolves to 'Samsung' via local database")
    func knownSamsungOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:00:F0:11:22:33")
        #expect(vendor == "Samsung")
    }

    @Test("Known Google OUI resolves to 'Google' via local database")
    func knownGoogleOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "3C:5A:B4:DE:AD:BE")
        #expect(vendor == "Google")
    }

    @Test("Known Amazon OUI resolves to 'Amazon' via local database")
    func knownAmazonOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:FC:8B:12:34:56")
        #expect(vendor == "Amazon")
    }

    @Test("Known Microsoft OUI resolves to 'Microsoft' via local database")
    func knownMicrosoftOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:03:FF:11:22:33")
        #expect(vendor == "Microsoft")
    }

    @Test("Known Intel OUI resolves to 'Intel' via local database")
    func knownIntelOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:02:B3:44:55:66")
        #expect(vendor == "Intel")
    }

    @Test("Known TP-Link OUI resolves to 'TP-Link' via local database")
    func knownTPLinkOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "10:FE:ED:AA:BB:CC")
        #expect(vendor == "TP-Link")
    }

    @Test("Known Netgear OUI resolves to 'Netgear' via local database")
    func knownNetgearOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:09:5B:11:22:33")
        #expect(vendor == "Netgear")
    }

    @Test("Known Cisco OUI resolves to 'Cisco' via local database")
    func knownCiscoOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:00:0C:DE:AD:BE")
        #expect(vendor == "Cisco")
    }

    @Test("Known Raspberry Pi OUI resolves to 'Raspberry Pi' via local database")
    func knownRaspberryPiOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "B8:27:EB:11:22:33")
        #expect(vendor == "Raspberry Pi")
    }

    @Test("Known Sonos OUI resolves to 'Sonos' via local database")
    func knownSonosOUI() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:0E:58:AA:BB:CC")
        #expect(vendor == "Sonos")
    }

    // MARK: - MAC Address Normalization

    @Test("lookup normalizes dash-separated lowercase MAC")
    func normalizesDashSeparated() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00-03-93-aa-bb-cc")
        #expect(vendor == "Apple")
    }

    @Test("lookup normalizes MAC without separators")
    func normalizesSeparatorFree() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "000393aabbcc")
        #expect(vendor == "Apple")
    }

    @Test("lookup normalizes mixed-case MAC")
    func normalizesMixedCase() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "00:03:93:Aa:Bb:Cc")
        #expect(vendor == "Apple")
    }

    // MARK: - Error / Edge Cases

    @Test("lookup returns nil for unknown OUI prefix")
    func unknownPrefixReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "12:34:56:78:90:AB")
        #expect(vendor == nil)
    }

    @Test("lookup returns nil for empty string")
    func emptyStringReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "")
        #expect(vendor == nil)
    }

    @Test("lookup returns nil for too-short MAC (less than 6 hex chars)")
    func tooShortMACReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "AA:BB")
        #expect(vendor == nil)
    }

    @Test("lookup returns nil for MAC with only 5 hex chars")
    func fiveCharMACReturnsNil() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookup(macAddress: "AABBC")
        #expect(vendor == nil)
    }

    @Test("lookup works with exactly 6 hex chars (minimum valid)")
    func sixCharMACWorks() async {
        let service = MACVendorLookupService()
        // "000393" should match Apple OUI "00:03:93"
        let vendor = await service.lookup(macAddress: "000393")
        #expect(vendor == "Apple")
    }

    @Test("enhancedLookup returns nil for too-short MAC")
    func enhancedLookupShortMAC() async {
        let service = MACVendorLookupService()
        let vendor = await service.lookupVendorEnhanced(macAddress: "AB")
        #expect(vendor == nil)
    }

    // MARK: - Multiple Vendor Coverage

    @Test("Multiple Apple OUI prefixes all resolve to 'Apple'")
    func multipleAppleOUIs() async {
        let service = MACVendorLookupService()
        let prefixes = ["00:03:93", "00:05:02", "00:0A:27", "00:F4:B9", "00:F7:6F"]
        for prefix in prefixes {
            let vendor = await service.lookup(macAddress: "\(prefix):11:22:33")
            #expect(vendor == "Apple", "Expected 'Apple' for OUI \(prefix)")
        }
    }

    @Test("Multiple Samsung OUI prefixes all resolve to 'Samsung'")
    func multipleSamsungOUIs() async {
        let service = MACVendorLookupService()
        let prefixes = ["00:00:F0", "00:02:78", "00:07:AB"]
        for prefix in prefixes {
            let vendor = await service.lookup(macAddress: "\(prefix):AA:BB:CC")
            #expect(vendor == "Samsung", "Expected 'Samsung' for OUI \(prefix)")
        }
    }
}
