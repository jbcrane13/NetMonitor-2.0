import Testing
@testable import NetMonitorCore

@Suite("MACAddress")
struct MACAddressTests {

    @Test("Locally administered addresses are private", arguments: [
        "02:11:22:33:44:55",
        "da:a1:19:00:00:01",
        "DA:A1:19:00:00:01",
        "3a-7b-00-11-22-33",
        "3A-7B-00-11-22-33",
        "f6d4880a1b2c",
        "2:11:22:33:44:55",
        "7e:0:1:2:3:4"
    ])
    func privateAddresses(mac: String) {
        #expect(MACAddress.isPrivate(mac))
    }

    @Test("Globally unique (maker-assigned) addresses are not private", arguments: [
        "00:03:93:AA:BB:CC",
        "b8:27:eb:11:22:33",
        "B8-27-EB-11-22-33",
        "000393aabbcc",
        "0:3:93:aa:bb:cc",
        "fc:fb:fb:01:02:03"
    ])
    func publicAddresses(mac: String) {
        #expect(!MACAddress.isPrivate(mac))
    }

    @Test("Empty or invalid input is not private", arguments: [
        "",
        "   ",
        "02",
        "02:11:22",
        "02:11:22:33:44",
        "02:11:22:33:44:55:66",
        "02:11:22:33:44:5G",
        "GG:HH:II:JJ:KK:LL",
        "02:111:22:33:44:55",
        "02::22:33:44:55",
        "0211223344",
        "02.11.22.33.44.55"
    ])
    func invalidInput(mac: String) {
        #expect(!MACAddress.isPrivate(mac))
    }

    @Test("Maker label shows the private label first, then a known vendor, then nothing")
    func makerLabel() {
        #expect(MACAddress.makerLabel(vendor: "Apple", macAddress: "00:03:93:aa:bb:cc") == "Apple")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "da:a1:19:00:00:01") == "Private address")
        #expect(MACAddress.makerLabel(vendor: "", macAddress: "da:a1:19:00:00:01") == "Private address")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "00:03:93:aa:bb:cc") == nil)
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: nil) == nil)
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "") == nil)
    }

    @Test("A private MAC with a stale stored vendor still shows the private label")
    func privateLabelBeatsStaleVendor() {
        #expect(MACAddress.makerLabel(vendor: "Apple, Inc.", macAddress: "DA-A1-19-00-00-01") == "Private address")
        #expect(MACAddress.makerLabel(vendor: "Stale Vendor", macAddress: "3a7b00112233") == "Private address")
    }

    @Test("The iOS hidden-address placeholder is not private")
    func hiddenPlaceholder() {
        #expect(!MACAddress.isPrivate("02:00:00:00:00:00"))
        #expect(!MACAddress.isPrivate("020000000000"))
    }

    @Test("The list maker label appends the model when known (#426)")
    func makerLabelWithModel() {
        #expect(MACAddress.makerLabel(vendor: "Apple", macAddress: "", model: "Mac16,11") == "Apple · Mac16,11")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: nil, model: "Arc Ultra") == "Arc Ultra")
        #expect(MACAddress.makerLabel(vendor: "Sonos", macAddress: nil, model: nil) == "Sonos")
        #expect(MACAddress.makerLabel(vendor: "Sonos", macAddress: nil, model: "  ") == "Sonos")
        #expect(MACAddress.makerLabel(vendor: "Roku", macAddress: nil, model: "Roku") == "Roku")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: nil, model: nil) == nil)
        #expect(MACAddress.makerLabel(vendor: "Apple", macAddress: "da:a1:19:00:00:01", model: "iPhone17,2") == "Private address · iPhone17,2")
    }
}
