import Testing
@testable import NetMonitorCore

@Suite("NetworkHealthScoreService")
struct NetworkHealthScoreServiceTests {

    // MARK: - computeScore (pure static function)

    @Test("Perfect metrics yield score in A range (90-100)")
    func perfectMetricsScoreA() {
        // latency <30 → 35/35, packetLoss 0 → 35/35, dns <50 → 20/20, devices normal → 10/10
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 10,
            packetLoss: 0,
            dnsMs: 20,
            deviceCount: 10,
            typicalDeviceCount: 10
        )
        #expect(score >= 90)
        #expect(score <= 100)
    }

    @Test("High latency (>200ms) reduces score to C/D range")
    func highLatencyReducesScore() {
        // latency ≥200 → 0/35, perfect everything else
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 250,
            packetLoss: 0,
            dnsMs: 20,
            deviceCount: 10,
            typicalDeviceCount: 10
        )
        // max achievable = (35 for loss + 20 for dns + 10 for devices) / 100 total = 65
        #expect(score < 80)
    }

    @Test("Packet loss >10% contributes 0 to loss component")
    func highPacketLossReducesScore() {
        // loss = 0.15 → 0/35; latency perfect → 35, dns perfect → 20, devices normal → 10
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 10,
            packetLoss: 0.15,
            dnsMs: 20,
            deviceCount: 10,
            typicalDeviceCount: 10
        )
        // (35 + 0 + 20 + 10) / (35+35+20+10) * 100 = 65/100 * 100 = 65
        #expect(score < 70)
    }

    @Test("No data at all returns score 0")
    func noDataReturnsZero() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        #expect(score == 0)
    }

    // MARK: - grade(for:)

    @Test("Grade A for score 90")
    func gradeA() {
        #expect(NetworkHealthScoreService.grade(for: 90) == "A")
        #expect(NetworkHealthScoreService.grade(for: 100) == "A")
    }

    @Test("Grade B for scores 80-89")
    func gradeB() {
        #expect(NetworkHealthScoreService.grade(for: 80) == "B")
        #expect(NetworkHealthScoreService.grade(for: 89) == "B")
    }

    @Test("Grade C for scores 70-79")
    func gradeC() {
        #expect(NetworkHealthScoreService.grade(for: 70) == "C")
        #expect(NetworkHealthScoreService.grade(for: 79) == "C")
    }

    @Test("Grade D for scores 60-69")
    func gradeD() {
        #expect(NetworkHealthScoreService.grade(for: 60) == "D")
        #expect(NetworkHealthScoreService.grade(for: 69) == "D")
    }

    @Test("Grade F for scores below 60")
    func gradeF() {
        #expect(NetworkHealthScoreService.grade(for: 59) == "F")
        #expect(NetworkHealthScoreService.grade(for: 0) == "F")
    }

    // MARK: - calculateScore (async, via update())

    @Test("Disconnected → score 0 and grade F")
    func disconnectedReturnsZero() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: 10,
            packetLoss: 0,
            dnsResponseMs: 20,
            deviceCount: 5,
            typicalDeviceCount: 5,
            isConnected: false
        )
        let result = await service.calculateScore()
        #expect(result.score == 0)
        #expect(result.grade == "F")
    }

    @Test("Scoring algorithm weight verification: latency 35 + loss 35 = 70 max points when dns/devices absent")
    func weightVerification() {
        // Only latency and packetLoss provided; perfect values each → total 70/70 → 100
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 10,
            packetLoss: 0,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        #expect(score == 100)
    }

    @Test("Moderate latency 60-100ms scores 22/35 for latency component")
    func moderateLatencyScore() {
        // latency 80ms → 22/35; no other metrics
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 80,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 22/35 * 100 = 62 (truncated Int)
        #expect(score == 62)
    }

    @Test("DNS 100-300ms scores 8/20 for dns component")
    func slowDNSScore() {
        // dns 200ms → 8/20; no other metrics
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: 200,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 8/20 * 100 = 40
        #expect(score == 40)
    }
}
