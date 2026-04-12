import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@MainActor
struct WakeOnLANToolViewModelTests {

    @Test func initialState() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        #expect(vm.macAddress == "")
        #expect(vm.broadcastAddress == "255.255.255.255")
        #expect(vm.isSending == false)
        #expect(vm.lastResult == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialMacAddressIsSet() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService(), initialMacAddress: "AA:BB:CC:DD:EE:FF")
        #expect(vm.macAddress == "AA:BB:CC:DD:EE:FF")
    }

    // MARK: - isValidMACAddress

    @Test func validMACAddressWithColons() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA:BB:CC:DD:EE:FF"
        #expect(vm.isValidMACAddress == true)
    }

    @Test func validMACAddressWithDashes() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA-BB-CC-DD-EE-FF"
        #expect(vm.isValidMACAddress == true)
    }

    @Test func validMACAddressNoDelimiters() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AABBCCDDEEFF"
        #expect(vm.isValidMACAddress == true)
    }

    @Test func validMACAddressLowercaseHex() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "aa:bb:cc:dd:ee:ff"
        #expect(vm.isValidMACAddress == true)
    }

    @Test func invalidMACAddressTooShort() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA:BB:CC:DD:EE"
        #expect(vm.isValidMACAddress == false)
    }

    @Test func invalidMACAddressTooLong() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA:BB:CC:DD:EE:FF:00"
        #expect(vm.isValidMACAddress == false)
    }

    @Test func invalidMACAddressNonHexChars() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "GG:HH:II:JJ:KK:LL"
        #expect(vm.isValidMACAddress == false)
    }

    @Test func invalidMACAddressEmpty() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = ""
        #expect(vm.isValidMACAddress == false)
    }

    // MARK: - formattedMACAddress

    @Test func formattedMACAddressFromRaw() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "aabbccddeeff"
        #expect(vm.formattedMACAddress == "AA:BB:CC:DD:EE:FF")
    }

    @Test func formattedMACAddressFromDashNotation() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA-BB-CC-DD-EE-FF"
        #expect(vm.formattedMACAddress == "AA:BB:CC:DD:EE:FF")
    }

    @Test func formattedMACAddressReturnedUnchangedWhenInvalid() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "ABC"
        #expect(vm.formattedMACAddress == "ABC")
    }

    // MARK: - canSend

    @Test func canSendTrueWithValidMAC() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA:BB:CC:DD:EE:FF"
        #expect(vm.canSend == true)
    }

    @Test func canSendFalseWithInvalidMAC() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "invalid"
        #expect(vm.canSend == false)
    }

    @Test func canSendFalseWhileSending() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.macAddress = "AA:BB:CC:DD:EE:FF"
        vm.isSending = true
        #expect(vm.canSend == false)
    }

    // MARK: - Actions

    @Test func clearResultsResetsState() {
        let vm = WakeOnLANToolViewModel(wolService: MockWakeOnLANService())
        vm.lastResult = WakeOnLANResult(macAddress: "AA:BB:CC:DD:EE:FF", success: true)
        vm.errorMessage = "some error"
        vm.clearResults()
        #expect(vm.lastResult == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func sendWakePacketSuccess() async {
        let mock = MockWakeOnLANService()
        mock.shouldSucceed = true
        let vm = WakeOnLANToolViewModel(wolService: mock)
        vm.macAddress = "AA:BB:CC:DD:EE:FF"
        await vm.sendWakePacket()
        #expect(vm.lastResult != nil)
        #expect(vm.lastResult?.success == true)
        #expect(vm.errorMessage == nil)
        #expect(vm.isSending == false)
    }

    @Test func sendWakePacketFailureSetsErrorMessage() async {
        let mock = MockWakeOnLANService()
        mock.shouldSucceed = false
        let vm = WakeOnLANToolViewModel(wolService: mock)
        vm.macAddress = "AA:BB:CC:DD:EE:FF"
        await vm.sendWakePacket()
        #expect(vm.errorMessage != nil)
        #expect(vm.isSending == false)
    }

    @Test func sendWakePacketIgnoredWhenCannotSend() async {
        let mock = MockWakeOnLANService()
        let vm = WakeOnLANToolViewModel(wolService: mock)
        vm.macAddress = "" // cannot send
        await vm.sendWakePacket()
        #expect(vm.lastResult == nil)
    }
}
