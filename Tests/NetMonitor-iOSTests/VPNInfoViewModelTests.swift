import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Mock VPN Service

private final class MockVPNDetectionService: VPNDetectionServiceProtocol, @unchecked Sendable {
    var mockStatus: VPNStatus = .inactive
    var startCallCount = 0
    var stopCallCount = 0

    var status: VPNStatus { mockStatus }

    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() { stopCallCount += 1 }

    func statusStream() -> AsyncStream<VPNStatus> {
        let s = mockStatus
        return AsyncStream { continuation in
            continuation.yield(s)
            continuation.finish()
        }
    }
}

// MARK: - Tests

@Suite("VPNInfoViewModel")
@MainActor
struct VPNInfoViewModelTests {

    @Test func initialStateIsInactive() {
        let vm = VPNInfoViewModel(service: MockVPNDetectionService())
        #expect(vm.isVPNActive == false)
        #expect(vm.interfaceName == "—")
        #expect(vm.protocolName == "Unknown")
        #expect(vm.statusText == "Not Connected")
        #expect(vm.connectionDuration == "")
    }

    @Test func statusTextConnectedWhenActive() {
        let mock = MockVPNDetectionService()
        mock.mockStatus = VPNStatus(
            isActive: true,
            interfaceName: "utun2",
            protocolType: .other
        )
        let vm = VPNInfoViewModel(service: mock)
        vm.vpnStatus = mock.mockStatus
        #expect(vm.statusText == "Connected")
        #expect(vm.isVPNActive == true)
    }

    @Test func interfaceNameDisplaysFromStatus() {
        let mock = MockVPNDetectionService()
        let vm = VPNInfoViewModel(service: mock)
        vm.vpnStatus = VPNStatus(isActive: true, interfaceName: "utun3", protocolType: .other)
        #expect(vm.interfaceName == "utun3")
    }

    @Test func interfaceNameEmDashWhenNil() {
        let mock = MockVPNDetectionService()
        let vm = VPNInfoViewModel(service: mock)
        vm.vpnStatus = VPNStatus(isActive: true, interfaceName: nil, protocolType: .unknown)
        #expect(vm.interfaceName == "—")
    }

    @Test func protocolNameDisplaysCorrectly() {
        let mock = MockVPNDetectionService()
        let vm = VPNInfoViewModel(service: mock)
        vm.vpnStatus = VPNStatus(isActive: true, interfaceName: "ipsec0", protocolType: .ipsec)
        #expect(vm.protocolName == "IPSec")
    }
}

// MARK: - VPN Protocol Type Tests

@Suite("VPNProtocolType")
struct VPNProtocolTypeTests {

    @Test func utunInterfaceDetectedAsOther() {
        let proto = VPNProtocolType.from(interfaceName: "utun2")
        #expect(proto == .other)
    }

    @Test func ipsecInterfaceDetected() {
        let proto = VPNProtocolType.from(interfaceName: "ipsec0")
        #expect(proto == .ipsec)
    }

    @Test func pppInterfaceDetected() {
        let proto = VPNProtocolType.from(interfaceName: "ppp0")
        #expect(proto == .pptp)
    }

    @Test func unknownPrefixReturnsUnknown() {
        let proto = VPNProtocolType.from(interfaceName: "en0")
        #expect(proto == .unknown)
    }

    @Test func rawValuesAreCorrect() {
        #expect(VPNProtocolType.wireguard.rawValue == "WireGuard")
        #expect(VPNProtocolType.ipsec.rawValue == "IPSec")
        #expect(VPNProtocolType.ikev2.rawValue == "IKEv2")
    }
}

// MARK: - VPNStatus Tests

@Suite("VPNStatus")
struct VPNStatusTests {

    @Test func inactiveStaticIsNotActive() {
        #expect(VPNStatus.inactive.isActive == false)
        #expect(VPNStatus.inactive.interfaceName == nil)
    }

    @Test func equatableForSameValues() {
        let a = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .other)
        let b = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .other)
        #expect(a == b)
    }

    @Test func equatableForDifferentValues() {
        let a = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .other)
        let b = VPNStatus(isActive: false)
        #expect(a != b)
    }
}
