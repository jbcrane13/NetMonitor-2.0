import Testing
@testable import NetMonitorCore

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

    // MARK: - Additional Grade Tests (6C)

    @Test("Grade boundary at 90 is A")
    func gradeBoundary90() {
        #expect(NetworkHealthScoreService.grade(for: 90) == "A")
    }

    @Test("Grade boundary at 89 is B")
    func gradeBoundary89() {
        #expect(NetworkHealthScoreService.grade(for: 89) == "B")
    }

    @Test("Grade boundary at 80 is B")
    func gradeBoundary80() {
        #expect(NetworkHealthScoreService.grade(for: 80) == "B")
    }

    @Test("Grade boundary at 79 is C")
    func gradeBoundary79() {
        #expect(NetworkHealthScoreService.grade(for: 79) == "C")
    }

    @Test("Grade boundary at 70 is C")
    func gradeBoundary70() {
        #expect(NetworkHealthScoreService.grade(for: 70) == "C")
    }

    @Test("Grade boundary at 69 is D")
    func gradeBoundary69() {
        #expect(NetworkHealthScoreService.grade(for: 69) == "D")
    }

    @Test("Grade boundary at 60 is D")
    func gradeBoundary60() {
        #expect(NetworkHealthScoreService.grade(for: 60) == "D")
    }

    @Test("Grade boundary at 59 is F")
    func gradeBoundary59() {
        #expect(NetworkHealthScoreService.grade(for: 59) == "F")
    }

    @Test("Score 0 yields grade F")
    func scoreZeroGradeF() {
        #expect(NetworkHealthScoreService.grade(for: 0) == "F")
    }

    @Test("Score 50 yields grade F")
    func score50GradeF() {
        #expect(NetworkHealthScoreService.grade(for: 50) == "F")
    }

    @Test("Score 100 yields grade A")
    func score100GradeA() {
        #expect(NetworkHealthScoreService.grade(for: 100) == "A")
    }

    // MARK: - Score Bounds (6C)

    @Test("computeScore does not exceed 100")
    func scoreDoesNotExceed100() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 1,
            packetLoss: 0,
            dnsMs: 1,
            deviceCount: 10,
            typicalDeviceCount: 10
        )
        #expect(score <= 100)
    }

    @Test("computeScore does not go below 0")
    func scoreDoesNotGoBelowZero() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 9999,
            packetLoss: 1.0,
            dnsMs: 9999,
            deviceCount: 100,
            typicalDeviceCount: 1
        )
        #expect(score >= 0)
    }

    // MARK: - Various Metric Input Combinations (6C)

    @Test("Packet loss under 1% scores 30/35")
    func packetLossUnder1Percent() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: 0.005,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 30/35 * 100 = 85
        #expect(score == 85)
    }

    @Test("Packet loss under 5% scores 20/35")
    func packetLossUnder5Percent() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: 0.03,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 20/35 * 100 = 57
        #expect(score == 57)
    }

    @Test("Packet loss under 10% scores 10/35")
    func packetLossUnder10Percent() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: 0.08,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 10/35 * 100 = 28
        #expect(score == 28)
    }

    @Test("DNS under 50ms scores 20/20")
    func dnsUnder50ms() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: 30,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 20/20 * 100 = 100
        #expect(score == 100)
    }

    @Test("DNS 50-100ms scores 15/20")
    func dns50to100ms() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: 75,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 15/20 * 100 = 75
        #expect(score == 75)
    }

    @Test("DNS >= 300ms scores 0/20")
    func dnsOver300ms() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: 500,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 0/20 * 100 = 0
        #expect(score == 0)
    }

    @Test("Device anomaly within normal range (0.5-1.5 ratio) scores 10/10")
    func deviceAnomalyNormal() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: 10,
            typicalDeviceCount: 10
        )
        // 10/10 * 100 = 100
        #expect(score == 100)
    }

    @Test("Device anomaly moderate (0.3-2.0 ratio) scores 6/10")
    func deviceAnomalyModerate() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: 18,
            typicalDeviceCount: 10
        )
        // 6/10 * 100 = 60
        #expect(score == 60)
    }

    @Test("Device anomaly extreme (outside 0.3-2.0 ratio) scores 2/10")
    func deviceAnomalyExtreme() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: 50,
            typicalDeviceCount: 10
        )
        // 2/10 * 100 = 20
        #expect(score == 20)
    }

    @Test("Latency 30-60ms scores 30/35")
    func latency30to60ms() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 45,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 30/35 * 100 = 85
        #expect(score == 85)
    }

    @Test("Latency 100-200ms scores 12/35")
    func latency100to200ms() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: 150,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil
        )
        // 12/35 * 100 = 34
        #expect(score == 34)
    }

    @Test("calculateScore populates details dictionary")
    func calculateScorePopulatesDetails() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: 25.0,
            packetLoss: 0.02,
            dnsResponseMs: 45.0,
            deviceCount: 8,
            typicalDeviceCount: 10,
            isConnected: true
        )
        let result = await service.calculateScore()
        #expect(result.details["latency"] != nil)
        #expect(result.details["packetLoss"] != nil)
        #expect(result.details["dns"] != nil)
        #expect(result.details["devices"] != nil)
    }

    @Test("calculateScore with no optional metrics still returns valid score")
    func calculateScoreNoOptionalMetrics() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: nil,
            packetLoss: nil,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: true
        )
        let result = await service.calculateScore()
        #expect(result.score == 0)
        #expect(result.grade == "F")
    }

    @Test("Device anomaly ignored when typicalDeviceCount is 0")
    func deviceAnomalyIgnoredWhenTypicalIsZero() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: 10,
            typicalDeviceCount: 0
        )
        // No data counted (typical is 0, guard fails), so 0
        #expect(score == 0)
    }

    @Test("Device anomaly ignored when deviceCount is nil")
    func deviceAnomalyIgnoredWhenCountNil() {
        let score = NetworkHealthScoreService.computeScore(
            latencyMs: nil,
            packetLoss: nil,
            dnsMs: nil,
            deviceCount: nil,
            typicalDeviceCount: 10
        )
        #expect(score == 0)
    }
}
