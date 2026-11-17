import Foundation
import Testing
@testable import NetMonitorCore

/// #384: the bundled IEEE MA-L maker list.
@Suite("OUIDatabase")
struct OUIDatabaseTests {

    @Test("The bundled list loads more than 30,000 prefixes")
    func bundledListIsLarge() {
        #expect(OUIDatabase.shared.count > 30000)
    }

    @Test("Prefixes outside the curated table resolve offline", arguments: [
        "28:6F:B9:11:22:33",
        "28:6f:b9:11:22:33",
        "28-6F-B9-11-22-33",
        "28-6f-b9-11-22-33",
        "286fb9112233"
    ])
    func ieeeOnlyPrefixResolves(mac: String) async {
        let vendor = await MACVendorLookupService().lookup(macAddress: mac)
        #expect(vendor == "Nokia Shanghai Bell Co., Ltd.")
    }

    @Test("Curated short names win over IEEE organisation names")
    func curatedNamesWin() async {
        #expect(await MACVendorLookupService().lookup(macAddress: "00:03:93:AA:BB:CC") == "Apple")
        #expect(OUIDatabase.vendor(forPrefix: "000393") == "Apple, Inc.")
    }

    @Test("Unknown prefixes and placeholders return nil")
    func unknownPrefixes() async {
        let service = MACVendorLookupService()
        #expect(await service.lookup(macAddress: "10:34:56:78:90:AB") == nil)
        #expect(await service.lookup(macAddress: "00:00:00:00:00:00") == nil)
        #expect(OUIDatabase.vendor(forPrefix: "103456") == nil)
        #expect(OUIDatabase.vendor(forPrefix: "GGHHII") == nil)
        #expect(OUIDatabase.vendor(forPrefix: "28:6F:B9") == nil)
    }

    @Test("No organisation is the IEEE 'Private' placeholder")
    func noPrivatePlaceholderNames() {
        #expect(!OUIDatabase.shared.values.contains { $0.caseInsensitiveCompare("Private") == .orderedSame })
    }

    @Test("Parsing skips comments and malformed lines")
    func parseSkipsBadLines() {
        let text = "# header\nABCDEF\tAcme\n12345\tShort\nGHIJKL\tNotHex\n123456\t\nnot a row\nabcdee\tLower\n"
        let vendors = OUIDatabase.parse(Data(text.utf8))
        #expect(vendors == [0xABCDEF: "Acme", 0xABCDEE: "Lower"])
    }
}
