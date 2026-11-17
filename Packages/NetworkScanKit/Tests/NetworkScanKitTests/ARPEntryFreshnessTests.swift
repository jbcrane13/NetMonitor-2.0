import Testing
@testable import NetworkScanKit

/// The `arp -anl` fallback (#401) and the "answered this scan" rule built on
/// ARP expiry (#378). All pure functions: no sysctl, no process, no clock.
struct ARPEntryFreshnessTests {

    // Captured from `arp -anl` on macOS 27.2 (mini-pro-1), trimmed.
    private static let listing = """
    Neighbor                Linklayer Address Expire(O) Expire(I)          Netif Refs Prbs
    169.254.38.16           (incomplete)      (none)    (none)         en0
    192.168.2.1             2a:70:4e:84:d1:70 2m6s      2m6s           en0    1
    192.168.2.1             2a:70:4e:84:d1:70 2m38s     2m38s          en1    1
    192.168.2.2             9c:5:d6:d5:87:9d  51s       51s            en0    1
    192.168.2.6             70:a7:41:d:9e:c5  expired   expired        en0    1
    192.168.2.16            d0:11:e5:28:8b:a0 (none)    (none)         en0
    192.168.2.255           ff:ff:ff:ff:ff:ff (none)    (none)         en0
    192.168.2.40            0:0:0:0:0:0       (none)    (none)         en1
    """

    @Test("parses complete entries and drops incomplete, broadcast and zero MACs")
    func parsesListing() {
        let entries = ARPCacheScanner.parseArpListing(Self.listing, now: 1_000)
        #expect(entries.map(\.ip) == ["192.168.2.1", "192.168.2.1", "192.168.2.2", "192.168.2.6", "192.168.2.16"])
    }

    @Test("zero-pads MAC octets the way the sysctl reader formats them")
    func zeroPadsMAC() {
        let entries = ARPCacheScanner.parseArpListing(Self.listing, now: 1_000)
        #expect(entries.first { $0.ip == "192.168.2.2" }?.mac == "9c:05:d6:d5:87:9d")
    }

    @Test("turns time left into an absolute expiry; expired is 1, (none) is 0")
    func mapsExpiry() {
        let entries = ARPCacheScanner.parseArpListing(Self.listing, now: 1_000)
        let byIP = ARPCacheScanner.expiryByIP(entries)
        let newest: Int32? = byIP["192.168.2.1"]
        #expect(newest == 1_158, "got \(String(describing: newest)) from \(entries)") // newest of 2m6s / 2m38s
        #expect(byIP["192.168.2.2"] == 1_051)
        #expect(byIP["192.168.2.6"] == 1)
        #expect(byIP["192.168.2.16"] == 0)
    }

    @Test("parses arp's compact durations", arguments: [
        ("51s", 51), ("2m6s", 126), ("1h2m3s", 3_723), ("10m", 600)
    ])
    func parsesDurations(text: String, seconds: Int) {
        #expect(ARPCacheScanner.parseDuration(Substring(text)) == Int32(seconds))
    }

    @Test("rejects text that is not a duration")
    func rejectsBadDurations() {
        #expect(ARPCacheScanner.parseDuration("") == nil)
        #expect(ARPCacheScanner.parseDuration("12") == nil)
        #expect(ARPCacheScanner.parseDuration("2x") == nil)
    }

    // MARK: - refreshedIPs (#378)

    private static func entry(_ ip: String, _ expiry: Int32) -> ARPEntry {
        ARPEntry(ip: ip, mac: "aa:bb:cc:dd:ee:ff", expiry: expiry)
    }

    @Test("an entry that appeared since the baseline counts as answered")
    func newEntryIsFresh() {
        let fresh = ARPCacheScanner.refreshedIPs(baseline: [:], current: [Self.entry("10.0.0.5", 500)])
        #expect(fresh == ["10.0.0.5"])
    }

    @Test("an expired entry that was re-confirmed counts as answered")
    func expiredThenRefreshedIsFresh() {
        let fresh = ARPCacheScanner.refreshedIPs(baseline: ["10.0.0.5": 1], current: [Self.entry("10.0.0.5", 1_150)])
        #expect(fresh == ["10.0.0.5"])
    }

    @Test("an entry that is only counting down does not count, even with a second of drift")
    func countdownIsNotFresh() {
        let fresh = ARPCacheScanner.refreshedIPs(
            baseline: ["10.0.0.5": 1_120, "10.0.0.6": 1],
            current: [Self.entry("10.0.0.5", 1_121), Self.entry("10.0.0.6", 1)]
        )
        #expect(fresh.isEmpty)
    }

    @Test("a zero expiry, before or after, proves nothing")
    func zeroExpiryIsNotFresh() {
        let fresh = ARPCacheScanner.refreshedIPs(
            baseline: ["10.0.0.5": 0, "10.0.0.6": 900],
            current: [Self.entry("10.0.0.5", 1_200), Self.entry("10.0.0.6", 0)]
        )
        #expect(fresh.isEmpty)
    }

    @Test("per-interface duplicates use the newest expiry")
    func duplicatesUseNewest() {
        let fresh = ARPCacheScanner.refreshedIPs(
            baseline: ["10.0.0.5": 100],
            current: [Self.entry("10.0.0.5", 50), Self.entry("10.0.0.5", 400)]
        )
        #expect(fresh == ["10.0.0.5"])
    }
}
