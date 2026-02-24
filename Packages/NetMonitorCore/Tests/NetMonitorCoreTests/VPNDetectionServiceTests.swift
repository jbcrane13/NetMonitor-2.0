import Foundation
import Testing
@testable import NetMonitorCore

@Suite("VPNDetectionService")
struct VPNDetectionServiceTests {

    // MARK: - VPNStatus model

    @Test("VPNStatus.inactive has isActive false")
    func inactiveStatusHasIsActiveFalse() {
        #expect(VPNStatus.inactive.isActive == false)
        #expect(VPNStatus.inactive.interfaceName == nil)
        #expect(VPNStatus.inactive.connectedSince == nil)
    }

    @Test("VPNStatus init stores all fields correctly")
    func vpnStatusInitStoresFields() {
        let now = Date()
        let status = VPNStatus(
            isActive: true,
            interfaceName: "utun2",
            protocolType: .wireguard,
            connectedSince: now
        )
        #expect(status.isActive == true)
        #expect(status.interfaceName == "utun2")
        #expect(status.protocolType == .wireguard)
        #expect(status.connectedSince == now)
    }

    @Test("VPNStatus Equatable: two identical inactive statuses are equal")
    func vpnStatusEquatable() {
        #expect(VPNStatus.inactive == VPNStatus.inactive)
    }

    // MARK: - VPNProtocolType.from(interfaceName:)

    @Test("utun prefix maps to .other protocol type")
    func utunMapsToOther() {
        #expect(VPNProtocolType.from(interfaceName: "utun0") == .other)
        #expect(VPNProtocolType.from(interfaceName: "utun2") == .other)
    }

    @Test("ipsec prefix maps to .ipsec protocol type")
    func ipsecMapsToIPSec() {
        #expect(VPNProtocolType.from(interfaceName: "ipsec0") == .ipsec)
    }

    @Test("ppp prefix maps to .pptp protocol type")
    func pppMapsToPPTP() {
        #expect(VPNProtocolType.from(interfaceName: "ppp0") == .pptp)
    }

    @Test("l2tp prefix maps to .l2tp protocol type")
    func l2tpMapsToL2TP() {
        #expect(VPNProtocolType.from(interfaceName: "l2tp0") == .l2tp)
    }

    @Test("ikev2 prefix maps to .ikev2 protocol type")
    func ikev2MapsToIKEv2() {
        #expect(VPNProtocolType.from(interfaceName: "ikev2") == .ikev2)
    }

    @Test("Unknown interface name maps to .unknown protocol type")
    func unknownInterfaceMapsToUnknown() {
        #expect(VPNProtocolType.from(interfaceName: "en0") == .unknown)
        #expect(VPNProtocolType.from(interfaceName: "wifi0") == .unknown)
    }

    // MARK: - VPNDetectionService lifecycle

    @Test("Service initial status is inactive")
    func serviceInitialStatusIsInactive() {
        let service = VPNDetectionService()
        #expect(service.status == VPNStatus.inactive)
    }

    @Test("statusStream immediately emits current status")
    func statusStreamEmitsImmediately() async {
        let service = VPNDetectionService()
        let stream = service.statusStream()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
        #expect(first?.isActive == false)
    }

    @Test("startMonitoring and stopMonitoring do not crash")
    func startStopMonitoringNoCrash() {
        let service = VPNDetectionService()
        service.startMonitoring()
        service.stopMonitoring()
        // Calling stop twice should also be safe
        service.stopMonitoring()
    }

    @Test("startMonitoring is idempotent — calling twice does not crash")
    func startMonitoringIdempotent() {
        let service = VPNDetectionService()
        service.startMonitoring()
        service.startMonitoring()
        service.stopMonitoring()
    }

    @Test("Multiple stream listeners receive initial status")
    func multipleStreamListeners() async {
        let service = VPNDetectionService()
        let stream1 = service.statusStream()
        let stream2 = service.statusStream()

        var it1 = stream1.makeAsyncIterator()
        var it2 = stream2.makeAsyncIterator()

        let first1 = await it1.next()
        let first2 = await it2.next()

        #expect(first1 != nil)
        #expect(first2 != nil)
        #expect(first1?.isActive == false)
        #expect(first2?.isActive == false)
    }
}

// MARK: - VPNProtocolType Edge Cases

@Suite("VPNProtocolType - Edge Cases")
struct VPNProtocolTypeEdgeCaseTests {

    @Test("Empty interface name maps to .unknown")
    func emptyStringMapsToUnknown() {
        #expect(VPNProtocolType.from(interfaceName: "") == .unknown)
    }

    @Test("Uppercase UTUN maps to .other (case-insensitive prefix check)")
    func uppercaseUtunMapsToOther() {
        // VPNProtocolType.from lowercases the input before prefix matching
        #expect(VPNProtocolType.from(interfaceName: "UTUN0") == .other)
    }

    @Test("utun without number suffix still maps to .other")
    func utunWithoutNumberMapsToOther() {
        #expect(VPNProtocolType.from(interfaceName: "utun") == .other)
    }

    @Test("ipsec with long suffix still maps to .ipsec")
    func ipsecLongSuffix() {
        #expect(VPNProtocolType.from(interfaceName: "ipsec123456") == .ipsec)
    }

    @Test("Mixed case PPP maps to .pptp")
    func mixedCasePPP() {
        #expect(VPNProtocolType.from(interfaceName: "Ppp0") == .pptp)
    }

    @Test("en0 is not a VPN interface")
    func en0NotVPN() {
        #expect(VPNProtocolType.from(interfaceName: "en0") == .unknown)
    }

    @Test("lo0 loopback is not a VPN interface")
    func loopbackNotVPN() {
        #expect(VPNProtocolType.from(interfaceName: "lo0") == .unknown)
    }

    @Test("bridge interface is not a VPN interface")
    func bridgeNotVPN() {
        #expect(VPNProtocolType.from(interfaceName: "bridge0") == .unknown)
    }
}

// MARK: - VPNStatus Equality

@Suite("VPNStatus - Equatable")
struct VPNStatusEqualityTests {

    @Test("Two active statuses with same fields are equal")
    func activeStatusesEqual() {
        let date = Date()
        let a = VPNStatus(isActive: true, interfaceName: "utun2", protocolType: .wireguard, connectedSince: date)
        let b = VPNStatus(isActive: true, interfaceName: "utun2", protocolType: .wireguard, connectedSince: date)
        #expect(a == b)
    }

    @Test("Active and inactive statuses are not equal")
    func activeAndInactiveNotEqual() {
        let active = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .other)
        #expect(active != VPNStatus.inactive)
    }

    @Test("Different protocol types are not equal")
    func differentProtocolsNotEqual() {
        let a = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .wireguard)
        let b = VPNStatus(isActive: true, interfaceName: "utun0", protocolType: .ipsec)
        #expect(a != b)
    }
}
