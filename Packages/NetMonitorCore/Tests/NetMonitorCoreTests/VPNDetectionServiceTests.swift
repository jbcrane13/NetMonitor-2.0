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
}
