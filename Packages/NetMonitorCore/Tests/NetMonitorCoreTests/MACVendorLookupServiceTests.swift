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
}
