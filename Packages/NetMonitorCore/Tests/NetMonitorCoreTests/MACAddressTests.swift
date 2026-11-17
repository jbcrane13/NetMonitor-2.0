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

    @Test("Maker label prefers a known vendor, then the private label, then nothing")
    func makerLabel() {
        #expect(MACAddress.makerLabel(vendor: "Apple", macAddress: "da:a1:19:00:00:01") == "Apple")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "da:a1:19:00:00:01") == "Private address")
        #expect(MACAddress.makerLabel(vendor: "", macAddress: "da:a1:19:00:00:01") == "Private address")
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "00:03:93:aa:bb:cc") == nil)
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: nil) == nil)
        #expect(MACAddress.makerLabel(vendor: nil, macAddress: "") == nil)
    }

    @Test("The iOS hidden-address placeholder is not private")
    func hiddenPlaceholder() {
        #expect(!MACAddress.isPrivate("02:00:00:00:00:00"))
        #expect(!MACAddress.isPrivate("020000000000"))
    }
}
