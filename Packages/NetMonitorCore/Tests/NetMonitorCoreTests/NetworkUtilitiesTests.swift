import Testing
@testable import NetMonitorCore

@Suite("NetworkUtilities")
struct NetworkUtilitiesTests {

    // MARK: - ipv4ToUInt32

    @Test("ipv4ToUInt32 converts valid addresses correctly")
    func ipv4ToUInt32ValidAddresses() {
        #expect(NetworkUtilities.ipv4ToUInt32("192.168.1.1") == 0xC0A80101)
        #expect(NetworkUtilities.ipv4ToUInt32("0.0.0.0") == 0)
        #expect(NetworkUtilities.ipv4ToUInt32("255.255.255.255") == 0xFFFFFFFF)
        #expect(NetworkUtilities.ipv4ToUInt32("10.0.0.1") == 0x0A000001)
        #expect(NetworkUtilities.ipv4ToUInt32("172.16.254.1") == 0xAC10FE01)
    }

    @Test("ipv4ToUInt32 returns nil for invalid inputs")
    func ipv4ToUInt32InvalidInputs() {
        #expect(NetworkUtilities.ipv4ToUInt32("") == nil)
        #expect(NetworkUtilities.ipv4ToUInt32("192.168.1") == nil)          // too few octets
        #expect(NetworkUtilities.ipv4ToUInt32("192.168.1.1.1") == nil)      // too many octets
        #expect(NetworkUtilities.ipv4ToUInt32("abc.def.ghi.jkl") == nil)    // non-numeric
        #expect(NetworkUtilities.ipv4ToUInt32("256.0.0.1") == nil)          // octet overflow (>255)
        #expect(NetworkUtilities.ipv4ToUInt32("192.168.1.-1") == nil)       // negative octet
        #expect(NetworkUtilities.ipv4ToUInt32("192.168.1.") == nil)         // trailing dot
    }

    // MARK: - uint32ToIPv4

    @Test("uint32ToIPv4 converts correctly")
    func uint32ToIPv4() {
        #expect(NetworkUtilities.uint32ToIPv4(0xC0A80101) == "192.168.1.1")
        #expect(NetworkUtilities.uint32ToIPv4(0) == "0.0.0.0")
        #expect(NetworkUtilities.uint32ToIPv4(0xFFFFFFFF) == "255.255.255.255")
        #expect(NetworkUtilities.uint32ToIPv4(0x0A000001) == "10.0.0.1")
    }

    @Test("ipv4ToUInt32 and uint32ToIPv4 round-trip")
    func roundTrip() {
        let addresses = ["192.168.1.1", "10.0.0.254", "172.16.0.1", "1.1.1.1", "8.8.8.8"]
        for addr in addresses {
            guard let value = NetworkUtilities.ipv4ToUInt32(addr) else {
                Issue.record("Expected valid IP: \(addr)")
                continue
            }
            #expect(NetworkUtilities.uint32ToIPv4(value) == addr)
        }
        // Boundary values
        #expect(NetworkUtilities.uint32ToIPv4(0) == "0.0.0.0")
        #expect(NetworkUtilities.uint32ToIPv4(UInt32.max) == "255.255.255.255")
    }

    // MARK: - IPv4Network.contains

    @Test("IPv4Network contains IP inside /24 network")
    func networkContainsIPInside() {
        // 192.168.1.0/24
        let netmask: UInt32 = 0xFFFFFF00
        let interfaceAddr: UInt32 = 0xC0A80164  // 192.168.1.100
        let networkAddr = interfaceAddr & netmask
        let broadcastAddr = networkAddr | ~netmask

        let network = NetworkUtilities.IPv4Network(
            networkAddress: networkAddr,
            broadcastAddress: broadcastAddr,
            interfaceAddress: interfaceAddr,
            netmask: netmask
        )

        #expect(network.contains(ipAddress: "192.168.1.1") == true)
        #expect(network.contains(ipAddress: "192.168.1.100") == true)
        #expect(network.contains(ipAddress: "192.168.1.254") == true)
        #expect(network.contains(ipAddress: "192.168.1.0") == true)   // network address
    }

    @Test("IPv4Network does not contain IP outside network")
    func networkContainsIPOutside() {
        let netmask: UInt32 = 0xFFFFFF00
        let interfaceAddr: UInt32 = 0xC0A80164  // 192.168.1.100
        let networkAddr = interfaceAddr & netmask
        let broadcastAddr = networkAddr | ~netmask

        let network = NetworkUtilities.IPv4Network(
            networkAddress: networkAddr,
            broadcastAddress: broadcastAddr,
            interfaceAddress: interfaceAddr,
            netmask: netmask
        )

        #expect(network.contains(ipAddress: "192.168.2.1") == false)
        #expect(network.contains(ipAddress: "10.0.0.1") == false)
        #expect(network.contains(ipAddress: "") == false)
        #expect(network.contains(ipAddress: "invalid") == false)
    }

    // MARK: - IPv4Network.prefixLength

    @Test("IPv4Network prefixLength matches netmask bit count")
    func networkPrefixLength() {
        // /24 — 24 bits set
        let net24 = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFFFF00
        )
        #expect(net24.prefixLength == 24)

        // /16 — 16 bits set
        let net16 = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80000,
            broadcastAddress: 0xC0A8FFFF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFF0000
        )
        #expect(net16.prefixLength == 16)

        // /8 — 8 bits set
        let net8 = NetworkUtilities.IPv4Network(
            networkAddress: 0x0A000000,
            broadcastAddress: 0x0AFFFFFF,
            interfaceAddress: 0x0A000001,
            netmask: 0xFF000000
        )
        #expect(net8.prefixLength == 8)
    }

    // MARK: - IPv4Network.hostAddresses

    @Test("hostAddresses returns requested count within /24")
    func hostAddressesCount() {
        // 192.168.1.0/24 — 254 hosts
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80164,  // 192.168.1.100
            netmask: 0xFFFFFF00
        )

        let addresses = network.hostAddresses(limit: 10)
        #expect(addresses.count == 10)
    }

    @Test("hostAddresses excludes interface address by default")
    func hostAddressesExcludesInterface() {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80164,  // 192.168.1.100
            netmask: 0xFFFFFF00
        )

        let addresses = network.hostAddresses(limit: 254)
        #expect(!addresses.contains("192.168.1.100"))
        #expect(addresses.count == 253)  // 254 hosts - 1 interface address
    }

    @Test("hostAddresses includes interface when excludingInterface is false")
    func hostAddressesIncludesInterface() {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80164,  // 192.168.1.100
            netmask: 0xFFFFFF00
        )

        let addresses = network.hostAddresses(limit: 254, excludingInterface: false)
        #expect(addresses.contains("192.168.1.100"))
        #expect(addresses.count == 254)
    }

    @Test("hostAddresses returns empty for zero limit")
    func hostAddressesZeroLimit() {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80164,
            netmask: 0xFFFFFF00
        )
        #expect(network.hostAddresses(limit: 0).isEmpty)
    }

    @Test("hostAddresses returns empty for point-to-point /31 equivalent")
    func hostAddressesPointToPoint() {
        // broadcastAddress - networkAddress == 1 means only 2 addresses, no valid host range
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A80101,
            interfaceAddress: 0xC0A80100,
            netmask: 0xFFFFFFFE
        )
        #expect(network.hostAddresses(limit: 10).isEmpty)
    }

    @Test("hostAddresses all returned addresses are valid IPv4 strings")
    func hostAddressesAreValidIPs() {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A80100,
            broadcastAddress: 0xC0A801FF,
            interfaceAddress: 0xC0A80101,
            netmask: 0xFFFFFF00
        )
        let addresses = network.hostAddresses(limit: 20, excludingInterface: false)
        for addr in addresses {
            let parts = addr.split(separator: ".")
            #expect(parts.count == 4)
        }
    }

    // MARK: - detectSubnet (system-dependent)

    @Test("detectSubnet returns three-octet prefix or nil")
    func detectSubnetFormat() {
        let result = NetworkUtilities.detectSubnet()
        if let subnet = result {
            let parts = subnet.split(separator: ".")
            #expect(parts.count == 3)
        }
        // nil is valid when no network interface is available in test environment
    }

    // MARK: - detectDefaultGateway (system-dependent)

    @Test("detectDefaultGateway returns valid IPv4 or nil")
    func detectDefaultGatewayFormat() {
        let result = NetworkUtilities.detectDefaultGateway()
        if let gateway = result {
            let parts = gateway.split(separator: ".")
            #expect(parts.count == 4)
        }
        // nil is valid when no network interface is available in test environment
    }
}
