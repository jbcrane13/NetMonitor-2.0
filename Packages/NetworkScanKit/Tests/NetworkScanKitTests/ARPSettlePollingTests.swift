import Testing
@testable import NetworkScanKit

/// `ARPCacheScanner.pollUntilSettled` replaces the fixed 2 s ARP wait (#379).
/// Every test injects the table reader and a no-op sleep, so none of them wait.
struct ARPSettlePollingTests {

    private static func entries(_ count: Int) -> [ARPEntry] {
        (0..<count).map { ARPEntry(ip: "192.168.1.\($0 + 1)", mac: "aa:bb:cc:00:00:\($0)", expiry: 100) }
    }

    @Test("stops after the quiet period when the table does not grow")
    func stopsWhenQuiet() async {
        var reads = 0
        let result = await ARPCacheScanner.pollUntilSettled(sleep: { _ in }, read: {
            reads += 1
            return Self.entries(3)
        })
        // Initial read, then two 250 ms polls with nothing new = 500 ms quiet.
        #expect(reads == 3)
        #expect(result.count == 3)
    }

    @Test("keeps polling while new IPs appear, then settles on the last read")
    func waitsForGrowthThenSettles() async {
        let sizes = [1, 2, 4, 4, 4, 4]
        var reads = 0
        let result = await ARPCacheScanner.pollUntilSettled(sleep: { _ in }, read: {
            defer { reads += 1 }
            return Self.entries(sizes[min(reads, sizes.count - 1)])
        })
        // Grows on reads 2 and 3, then two quiet polls.
        #expect(reads == 5)
        #expect(result.count == 4)
    }

    @Test("never waits longer than the cap, even if the table keeps growing")
    func honorsCap() async {
        var reads = 0
        var slept: Duration = .zero
        let result = await ARPCacheScanner.pollUntilSettled(sleep: { _ in }, read: {
            reads += 1
            return Self.entries(reads)
        })
        slept = .milliseconds(250) * (reads - 1)
        // 2 s cap / 250 ms = 8 polls after the initial read.
        #expect(reads == 9)
        #expect(slept == .seconds(2))
        #expect(result.count == 9)
    }

    @Test("an entry leaving the table does not count as growth")
    func shrinkingIsQuiet() async {
        let sizes = [3, 2, 2]
        var reads = 0
        _ = await ARPCacheScanner.pollUntilSettled(sleep: { _ in }, read: {
            defer { reads += 1 }
            return Self.entries(sizes[min(reads, sizes.count - 1)])
        })
        #expect(reads == 3)
    }

    @Test("stops at once when the task is cancelled instead of spinning to the cap")
    func stopsWhenCancelled() async {
        let reads = await Task { () -> Int in
            var reads = 0
            _ = await ARPCacheScanner.pollUntilSettled(sleep: { _ in }, read: {
                reads += 1
                withUnsafeCurrentTask { $0?.cancel() }
                return Self.entries(reads)
            })
            return reads
        }.value
        #expect(reads == 1)
    }
}
