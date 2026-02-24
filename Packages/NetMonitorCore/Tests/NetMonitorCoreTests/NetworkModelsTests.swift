import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - NetworkStatus

@Suite("NetworkStatus")
struct NetworkStatusTests {
    @Test func defaultInitHasExpectedValues() {
        let status = NetworkStatus()
        #expect(status.connectionType == .none)
        #expect(status.isConnected == false)
        #expect(status.isExpensive == false)
        #expect(status.isConstrained == false)
        #expect(status.wifi == nil)
        #expect(status.gateway == nil)
        #expect(status.publicIP == nil)
    }

    @Test func staticDisconnectedIsDisconnected() {
        let status = NetworkStatus.disconnected
        #expect(status.connectionType == .none)
        #expect(status.isConnected == false)
        #expect(status.wifi == nil)
        #expect(status.gateway == nil)
        #expect(status.publicIP == nil)
    }

    @Test func initWithAllParameters() {
        let wifi = WiFiInfo(ssid: "TestNet", signalDBm: -55)
        let gateway = GatewayInfo(ipAddress: "192.168.1.1")
        let status = NetworkStatus(
            connectionType: .wifi,
            isConnected: true,
            isExpensive: true,
            isConstrained: false,
            wifi: wifi,
            gateway: gateway
        )
        #expect(status.connectionType == .wifi)
        #expect(status.isConnected == true)
        #expect(status.isExpensive == true)
        #expect(status.isConstrained == false)
        #expect(status.wifi?.ssid == "TestNet")
        #expect(status.gateway?.ipAddress == "192.168.1.1")
    }
}

// MARK: - WiFiInfo signalQuality

@Suite("WiFiInfo.signalQuality")
struct WiFiInfoSignalQualityTests {
    @Test func nilDbmIsUnknown() {
        let wifi = WiFiInfo(ssid: "Net")
        #expect(wifi.signalQuality == .unknown)
    }

    @Test func zeroDbmIsExcellent() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: 0)
        #expect(wifi.signalQuality == .excellent)
    }

    @Test func minus50IsExcellentBoundary() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -50)
        #expect(wifi.signalQuality == .excellent)
    }

    @Test func minus51IsGood() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -51)
        #expect(wifi.signalQuality == .good)
    }

    @Test func minus60IsGood() {
        // -60 ..< -50 includes -60
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -60)
        #expect(wifi.signalQuality == .good)
    }

    @Test func minus61IsFair() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -61)
        #expect(wifi.signalQuality == .fair)
    }

    @Test func minus70IsFair() {
        // -70 ..< -60 includes -70
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -70)
        #expect(wifi.signalQuality == .fair)
    }

    @Test func minus71IsPoor() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -71)
        #expect(wifi.signalQuality == .poor)
    }

    @Test func minus90IsPoor() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -90)
        #expect(wifi.signalQuality == .poor)
    }
}

// MARK: - WiFiInfo signalBars

@Suite("WiFiInfo.signalBars")
struct WiFiInfoSignalBarsTests {
    @Test func nilDbmIsZeroBars() {
        let wifi = WiFiInfo(ssid: "Net")
        #expect(wifi.signalBars == 0)
    }

    @Test func zeroDbmIs4Bars() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: 0)
        #expect(wifi.signalBars == 4)
    }

    @Test func minus50Is4Bars() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -50)
        #expect(wifi.signalBars == 4)
    }

    @Test func minus51Is3Bars() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -51)
        #expect(wifi.signalBars == 3)
    }

    @Test func minus60Is3Bars() {
        // -60 ..< -50 includes -60
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -60)
        #expect(wifi.signalBars == 3)
    }

    @Test func minus61Is2Bars() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -61)
        #expect(wifi.signalBars == 2)
    }

    @Test func minus70Is2Bars() {
        // -70 ..< -60 includes -70
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -70)
        #expect(wifi.signalBars == 2)
    }

    @Test func minus71Is1Bar() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -71)
        #expect(wifi.signalBars == 1)
    }

    @Test func minus80Is1Bar() {
        // -80 ..< -70 includes -80
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -80)
        #expect(wifi.signalBars == 1)
    }

    @Test func minus81IsZeroBars() {
        let wifi = WiFiInfo(ssid: "Net", signalDBm: -81)
        #expect(wifi.signalBars == 0)
    }
}

// MARK: - GatewayInfo.latencyText

@Suite("GatewayInfo.latencyText")
struct GatewayInfoLatencyTextTests {
    @Test func nilLatencyReturnsNil() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1")
        #expect(gateway.latencyText == nil)
    }

    @Test func subOneMillisecondReturnsLessThan1ms() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1", latency: 0.5)
        #expect(gateway.latencyText == "<1 ms")
    }

    @Test func zeroLatencyReturnsLessThan1ms() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1", latency: 0.0)
        #expect(gateway.latencyText == "<1 ms")
    }

    @Test func exactly1msFormatsCorrectly() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1", latency: 1.0)
        #expect(gateway.latencyText == "1 ms")
    }

    @Test func roundsToNearestMs() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1", latency: 25.7)
        #expect(gateway.latencyText == "26 ms")
    }

    @Test func largeLatencyFormatsCorrectly() {
        let gateway = GatewayInfo(ipAddress: "192.168.1.1", latency: 200.0)
        #expect(gateway.latencyText == "200 ms")
    }
}

// MARK: - ISPInfo.locationText

@Suite("ISPInfo.locationText")
struct ISPInfoLocationTextTests {
    @Test func cityAndCountryCodeProducesCommaSeparated() {
        let isp = ISPInfo(publicIP: "1.2.3.4", city: "San Francisco", countryCode: "US")
        #expect(isp.locationText == "San Francisco, US")
    }

    @Test func noCountryCodeFallsBackToCountry() {
        let isp = ISPInfo(publicIP: "1.2.3.4", city: "London", country: "United Kingdom")
        #expect(isp.locationText == "London, United Kingdom")
    }

    @Test func countryCodeTakesPrecedenceOverCountry() {
        let isp = ISPInfo(publicIP: "1.2.3.4", city: "Paris", country: "France", countryCode: "FR")
        #expect(isp.locationText == "Paris, FR")
    }

    @Test func noCityOnlyCountryCode() {
        let isp = ISPInfo(publicIP: "1.2.3.4", countryCode: "DE")
        #expect(isp.locationText == "DE")
    }

    @Test func cityOnlyNoCountry() {
        let isp = ISPInfo(publicIP: "1.2.3.4", city: "Tokyo")
        #expect(isp.locationText == "Tokyo")
    }

    @Test func noCityNoCountryReturnsNil() {
        let isp = ISPInfo(publicIP: "1.2.3.4")
        #expect(isp.locationText == nil)
    }

    @Test func allNilLocationReturnsNil() {
        let isp = ISPInfo(publicIP: "8.8.8.8", city: nil, region: nil, country: nil, countryCode: nil)
        #expect(isp.locationText == nil)
    }
}

// MARK: - NetworkProfile Extended Tests

@Suite("NetworkProfile Extended")
struct NetworkProfileExtendedTests {

    private func makeNetwork() -> NetworkUtilities.IPv4Network {
        // 192.168.1.0/24
        NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFFFF00
        )
    }

    private func makeProfile(id: UUID = UUID()) -> NetworkProfile {
        NetworkProfile(
            id: id,
            interfaceName: "en0",
            ipAddress: "192.168.1.1",
            network: makeNetwork(),
            connectionType: .wifi,
            name: "Home Wi-Fi",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
    }

    // MARK: - Equatable

    @Test func equatableSameIDIsEqual() {
        let id = UUID()
        let p1 = makeProfile(id: id)
        let p2 = makeProfile(id: id)
        #expect(p1 == p2)
    }

    @Test func equatableDifferentIDIsNotEqual() {
        let p1 = makeProfile(id: UUID())
        let p2 = makeProfile(id: UUID())
        #expect(p1 != p2)
    }

    // MARK: - Hashable (Set storage)

    @Test func hashableAllowsSetDeduplication() {
        let id = UUID()
        let p1 = makeProfile(id: id)
        let p2 = makeProfile(id: id)
        let p3 = makeProfile(id: UUID())
        let set: Set<NetworkProfile> = [p1, p2, p3]
        #expect(set.count == 2)
    }

    @Test func hashableSetContainment() {
        let id = UUID()
        let profile = makeProfile(id: id)
        var set: Set<NetworkProfile> = []
        set.insert(profile)
        #expect(set.contains(profile))
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let id = UUID()
        let original = makeProfile(id: id)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkProfile.self, from: encoded)

        #expect(decoded.id == id)
        #expect(decoded.interfaceName == "en0")
        #expect(decoded.ipAddress == "192.168.1.1")
        #expect(decoded.connectionType == .wifi)
        #expect(decoded.name == "Home Wi-Fi")
        #expect(decoded.gatewayIP == "192.168.1.1")
        #expect(decoded.subnet == "192.168.1.0/24")
        #expect(decoded.isLocal == true)
        #expect(decoded.discoveryMethod == .auto)
    }

    @Test func codableRoundTripPreservesOptionalFields() throws {
        let scannedDate = Date(timeIntervalSinceReferenceDate: 1_500_000)
        var profile = makeProfile()
        profile = NetworkProfile(
            id: profile.id,
            interfaceName: profile.interfaceName,
            ipAddress: profile.ipAddress,
            network: profile.network,
            connectionType: profile.connectionType,
            name: profile.name,
            gatewayIP: profile.gatewayIP,
            subnet: profile.subnet,
            isLocal: profile.isLocal,
            discoveryMethod: profile.discoveryMethod,
            lastScanned: scannedDate,
            deviceCount: 12,
            gatewayReachable: true
        )

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(NetworkProfile.self, from: encoded)

        #expect(decoded.deviceCount == 12)
        #expect(decoded.gatewayReachable == true)
        #expect(decoded.lastScanned != nil)
        if let ts = decoded.lastScanned {
            #expect(abs(ts.timeIntervalSince(scannedDate)) < 0.001)
        }
    }
}
