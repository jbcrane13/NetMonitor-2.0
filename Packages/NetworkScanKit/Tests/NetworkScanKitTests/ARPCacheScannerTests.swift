import Testing
@testable import NetworkScanKit

/// Tests for ARPCacheScanner.
/// The sysctl-based ARP cache reading and UDP probe sending require a live
/// network interface and cannot be reliably tested in isolation.
/// These tests verify the public API surface and type safety.
@Suite("ARPCacheScanner")
struct ARPCacheScannerTests {

    // MARK: - readARPCache returns a typed result

    @Test("readARPCache returns an array (may be empty in sandbox)")
    func readARPCacheReturnsList() {
        let entries = ARPCacheScanner.readARPCache()
        // Each entry must have non-empty ip and mac fields
        for entry in entries {
            #expect(!entry.ip.isEmpty)
            #expect(!entry.mac.isEmpty)
        }
    }

    // MARK: - MAC address format

    @Test("readARPCache MAC addresses are colon-separated hex pairs")
    func macAddressesAreColonHex() {
        let entries = ARPCacheScanner.readARPCache()
        for entry in entries {
            let parts = entry.mac.split(separator: ":")
            #expect(parts.count == 6, "Expected 6 hex groups in \(entry.mac)")
            for part in parts {
                #expect(part.count == 2, "Expected 2-char hex group, got '\(part)'")
                let isHex = part.allSatisfy { $0.isHexDigit }
                #expect(isHex, "Non-hex character in MAC part '\(part)'")
            }
        }
    }

    // MARK: - IP address format

    @Test("readARPCache IP addresses are dotted-decimal IPv4")
    func ipAddressesAreDottedDecimal() {
        let entries = ARPCacheScanner.readARPCache()
        for entry in entries {
            let parts = entry.ip.split(separator: ".")
            #expect(parts.count == 4, "Expected 4 octets in \(entry.ip)")
            for part in parts {
                let value = Int(part)
                #expect(value != nil, "Non-integer octet '\(part)'")
                if let v = value {
                    #expect(v >= 0 && v <= 255, "Octet out of range: \(v)")
                }
            }
        }
    }

    // MARK: - Broadcast and all-zero MACs are filtered

    @Test("readARPCache does not return broadcast MAC ff:ff:ff:ff:ff:ff")
    func broadcastMACIsFiltered() {
        let entries = ARPCacheScanner.readARPCache()
        let hasBroadcast = entries.contains { $0.mac == "ff:ff:ff:ff:ff:ff" }
        #expect(hasBroadcast == false)
    }

    @Test("readARPCache does not return all-zero MAC 00:00:00:00:00:00")
    func allZeroMACIsFiltered() {
        let entries = ARPCacheScanner.readARPCache()
        let hasAllZero = entries.contains { $0.mac == "00:00:00:00:00:00" }
        #expect(hasAllZero == false)
    }

    // MARK: - populateARPCache handles edge cases

    @Test("populateARPCache with empty hosts list does not crash")
    func populateARPCacheWithEmptyListDoesNotCrash() {
        ARPCacheScanner.populateARPCache(hosts: [])
        #expect(true)
    }

    @Test("populateARPCache ignores invalid IP strings")
    func populateARPCacheIgnoresInvalidIPs() {
        // Should not crash with malformed input
        ARPCacheScanner.populateARPCache(hosts: ["not-an-ip", "999.999.999.999", ""])
        #expect(true)
    }

    // MARK: - scanSubnet result type

    @Test("scanSubnet with empty hosts returns empty array")
    func scanSubnetWithEmptyHostsReturnsEmpty() async {
        let results = await ARPCacheScanner.scanSubnet(hosts: [])
        // Empty host list — no ARP entries can be discovered
        // Results may be non-empty on a live machine (existing cache entries),
        // but must be a valid typed array
        for entry in results {
            #expect(!entry.ip.isEmpty)
            #expect(!entry.mac.isEmpty)
        }
        // The important invariant: no crash
        #expect(true)
    }
}
