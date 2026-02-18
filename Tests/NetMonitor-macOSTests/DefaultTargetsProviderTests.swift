import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("DefaultTargetsProvider")
struct DefaultTargetsProviderTests {

    @Test func userDefaultsKeyValue() {
        #expect(DefaultTargetsProvider.userDefaultsKey == "netmonitor.hasSeededDefaultTargets")
    }

    @Test func defaultTargetsCountIsSix() {
        #expect(DefaultTargetsProvider.defaultTargets.count == 6)
    }

    @Test func defaultTargetsContainGateway() {
        let names = DefaultTargetsProvider.defaultTargets.map { $0.name }
        #expect(names.contains("Gateway"))
    }

    @Test func defaultTargetsContainCloudflareDNS() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.contains("1.1.1.1"))
    }

    @Test func defaultTargetsContainGoogleDNS() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.contains("8.8.8.8"))
    }

    @Test func defaultTargetsContainQuad9DNS() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.contains("9.9.9.9"))
    }

    @Test func defaultTargetsContainGoogleHost() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.contains("google.com"))
    }

    @Test func defaultTargetsContainAppleHost() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.contains("apple.com"))
    }

    @Test func httpsTargetsCount() {
        // google.com and apple.com are HTTPS
        let httpsTargets = DefaultTargetsProvider.defaultTargets.filter { $0.2 == .https }
        #expect(httpsTargets.count == 2)
    }

    @Test func icmpTargetsCount() {
        // Gateway + Cloudflare + Google DNS + Quad9 = 4 ICMP
        let icmpTargets = DefaultTargetsProvider.defaultTargets.filter { $0.2 == .icmp }
        #expect(icmpTargets.count == 4)
    }

    @Test func gatewayUsesICMPProtocol() {
        let gateway = DefaultTargetsProvider.defaultTargets.first { $0.name == "Gateway" }
        #expect(gateway != nil)
        #expect(gateway?.2 == .icmp)
    }

    @Test func gatewayIntervalIs30Seconds() {
        let gateway = DefaultTargetsProvider.defaultTargets.first { $0.name == "Gateway" }
        #expect(gateway?.interval == 30)
    }

    @Test func httpsTargetsHave60SecondInterval() {
        let httpsTargets = DefaultTargetsProvider.defaultTargets.filter { $0.2 == .https }
        #expect(httpsTargets.allSatisfy { $0.interval == 60 })
    }

    @Test func icmpTargetsHave30SecondInterval() {
        let icmpTargets = DefaultTargetsProvider.defaultTargets.filter { $0.2 == .icmp }
        #expect(icmpTargets.allSatisfy { $0.interval == 30 })
    }

    @Test func allTargetNamesAreNonEmpty() {
        let names = DefaultTargetsProvider.defaultTargets.map { $0.name }
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func allTargetHostsAreNonEmpty() {
        let hosts = DefaultTargetsProvider.defaultTargets.map { $0.host }
        #expect(hosts.allSatisfy { !$0.isEmpty })
    }
}
