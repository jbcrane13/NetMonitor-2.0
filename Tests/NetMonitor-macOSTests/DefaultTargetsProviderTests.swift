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

    // MARK: - Default targets loaded correctly

    @Test func defaultTargetsContainExpectedNames() {
        let names = DefaultTargetsProvider.defaultTargets.map { $0.name }
        let expectedNames = ["Gateway", "Cloudflare DNS", "Google DNS", "Quad9 DNS", "Google", "Apple"]
        for name in expectedNames {
            #expect(names.contains(name), "Missing target: \(name)")
        }
    }

    @Test func defaultTargetsHaveUniqueNames() {
        let names = DefaultTargetsProvider.defaultTargets.map { $0.name }
        let uniqueNames = Set(names)
        #expect(uniqueNames.count == names.count, "Target names should be unique")
    }

    @Test func defaultTargetsHavePositiveIntervals() {
        for target in DefaultTargetsProvider.defaultTargets {
            #expect(target.interval > 0, "\(target.name) should have a positive check interval")
        }
    }

    @Test func gatewayTargetUsesPlaceholderHost() {
        let gateway = DefaultTargetsProvider.defaultTargets.first { $0.name == "Gateway" }
        #expect(gateway?.host == "GATEWAY_IP",
                "Gateway target should use GATEWAY_IP placeholder for runtime detection")
    }

    @Test func dnsTargetsUseIPAddresses() {
        let dnsTargets = DefaultTargetsProvider.defaultTargets.filter {
            $0.name.contains("DNS")
        }
        for target in dnsTargets {
            // All DNS targets should be IP addresses (contain dots, no alpha)
            let isIP = target.host.split(separator: ".").count == 4
            #expect(isIP, "\(target.name) host should be an IP address")
        }
    }

    @Test func httpsTargetsUseDomainNames() {
        let httpsTargets = DefaultTargetsProvider.defaultTargets.filter { $0.2 == .https }
        for target in httpsTargets {
            #expect(target.host.contains("."), "\(target.name) should use a domain name")
            // Should not be an IP address
            let parts = target.host.split(separator: ".")
            let looksLikeIP = parts.count == 4 && parts.allSatisfy { Int($0) != nil }
            #expect(!looksLikeIP, "\(target.name) HTTPS target should be a domain, not an IP")
        }
    }

    // MARK: - Fallback behavior

    @Test func userDefaultsKeyIsStable() {
        // Verify the key doesn't change accidentally — it controls seeding behavior
        #expect(DefaultTargetsProvider.userDefaultsKey == "netmonitor.hasSeededDefaultTargets")
    }

    @Test func defaultTargetsArrayIsNotEmpty() {
        #expect(!DefaultTargetsProvider.defaultTargets.isEmpty,
                "Default targets must not be empty for first-launch seeding")
    }

    @Test func allTargetProtocolsAreICMPOrHTTPS() {
        for target in DefaultTargetsProvider.defaultTargets {
            let proto = target.2
            #expect(proto == .icmp || proto == .https,
                    "\(target.name) should use ICMP or HTTPS protocol")
        }
    }
}
