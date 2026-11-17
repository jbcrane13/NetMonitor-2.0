import Testing
@testable import NetworkScanKit

/// The "answered this scan" rule built on ARP expiry (#378).
/// All pure functions: no sysctl, no clock.
struct ARPEntryFreshnessTests {

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

    @Test("a new entry counts as answered even with a zero expiry")
    func newZeroExpiryEntryIsFresh() {
        let fresh = ARPCacheScanner.refreshedIPs(baseline: ["10.0.0.6": 900], current: [Self.entry("10.0.0.5", 0)])
        #expect(fresh == ["10.0.0.5"])
    }

    @Test("a zero expiry on an entry already in the baseline proves nothing")
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
