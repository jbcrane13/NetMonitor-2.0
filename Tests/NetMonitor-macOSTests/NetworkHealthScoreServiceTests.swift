import Testing
import Foundation
import NetMonitorCore

// MARK: - NetworkHealthScoreService.computeScore Tests

// NetworkHealthScoreService.computeScore is internal (not public), so we test via
// the public calculateScore() async path for the full service, and via the static
// method directly here because the test target imports NetMonitorCore (not @testable,
// so only public API is available — see note below).
//
// NOTE: computeScore and grade(for:) are declared `static func` with no access
// modifier, which makes them `internal`. They are accessible from this test target
// only if the test target is within the same module OR via @testable import.
// The NetworkHealthScoreService lives in NetMonitorCore package, so we test the
// full observable behavior via update() + calculateScore().

@Suite("NetworkHealthScoreService – computeScore (via update+calculateScore)")
struct NetworkHealthScoreComputeScoreTests {

    // MARK: No data

    @Test func noDataReturnsScoreZero() async {
        let service = NetworkHealthScoreService()
        // No update called — all fields default to nil / isConnected = true
        // With no data, computeScore returns 0
        let result = await service.calculateScore()
        #expect(result.score == 0)
    }

    // MARK: isConnected false

    @Test func notConnectedReturnsScoreZeroGradeF() async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: 25,
            packetLoss: 0.0,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: false
        )
        let result = await service.calculateScore()
        #expect(result.score == 0)
        #expect(result.grade == "F")
    }

    // MARK: Latency only tests
    // When only latency is provided: maxTotal=35, score = Int(latencyScore / 35 * 100)
    // <30ms → 35pts → 100
    // 30-60ms → 30pts → Int(30/35*100) = Int(85.71) = 85
    // 60-100ms → 22pts → Int(22/35*100) = Int(62.857) = 62
    // 100-200ms → 12pts → Int(12/35*100) = Int(34.28) = 34
    // >=200ms → 0pts → 0

    @Test func latencyZeroMsScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 0, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 100)
    }

    @Test func latency29MsScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 29, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 100)
    }

    @Test func latency30MsScoreIs85() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 30, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 30/35 * 100 = 85.71... → Int = 85
        #expect(result.score == 85)
    }

    @Test func latency60MsScoreIs62() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 60, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 22/35 * 100 = 62.857... → Int = 62
        #expect(result.score == 62)
    }

    @Test func latency100MsScoreIs34() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 100, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 12/35 * 100 = 34.285... → Int = 34
        #expect(result.score == 34)
    }

    @Test func latency200MsScoreIsZero() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 200, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // >= 200ms → 0pts → 0/35*100 = 0
        #expect(result.score == 0)
    }

    // MARK: Packet loss only tests
    // When only packetLoss provided: maxTotal=35
    // 0.0 exactly → 35pts → 100
    // > 0 and < 0.01 → 30pts → Int(30/35*100) = 85
    // 0.01..<0.05 → 20pts → Int(20/35*100) = 57
    // 0.05..<0.10 → 10pts → Int(10/35*100) = 28
    // >= 0.10 → 0pts → 0

    @Test func packetLossZeroScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 100)
    }

    @Test func packetLossHalfPercentScoreIs85() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.005, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 0.005 is > 0 and < 0.01 → 30pts → 85
        #expect(result.score == 85)
    }

    @Test func packetLossOnePercentScoreIs57() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.01, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 0.01 is >= 0.01 and < 0.05 → 20pts → Int(20/35*100) = 57
        #expect(result.score == 57)
    }

    @Test func packetLossFivePercentScoreIs28() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.05, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // 0.05 is >= 0.05 and < 0.10 → 10pts → Int(10/35*100) = 28
        #expect(result.score == 28)
    }

    @Test func packetLossTenPercentScoreIsZero() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.10, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // >= 0.10 → 0pts → 0
        #expect(result.score == 0)
    }

    // MARK: Combined latency + packet loss

    @Test func latency25MsAndZeroLossScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 25, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // latency < 30ms → 35pts, loss == 0 → 35pts, total=70, max=70 → 100
        #expect(result.score == 100)
    }

    @Test func latency30MsAndHalfPercentLossScoreIs85() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 30, packetLoss: 0.005, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // latency 30ms → 30pts, loss 0.005 → 30pts, total=60, max=70 → Int(60/70*100) = Int(85.71) = 85
        #expect(result.score == 85)
    }

    // MARK: Device anomaly

    @Test func deviceCountEqualToTypicalScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: 10, typicalDeviceCount: 10, isConnected: true)
        let result = await service.calculateScore()
        // ratio = 1.0 → 0.5..<1.5 → 10pts, maxTotal=10 → 100
        #expect(result.score == 100)
    }

    @Test func deviceCountFarBelowTypicalScoreIs20() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: 1, typicalDeviceCount: 10, isConnected: true)
        let result = await service.calculateScore()
        // ratio = 0.1 → default case → 2pts, maxTotal=10 → Int(2/10*100) = 20
        #expect(result.score == 20)
    }

    @Test func deviceCountSlightlyBelowTypicalScoreIs60() async {
        // ratio 0.4 → 0.3..<2.0 but outside 0.5..<1.5 → 6pts → Int(6/10*100) = 60
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: 4, typicalDeviceCount: 10, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 60)
    }

    @Test func typicalDeviceCountZeroIgnoresDeviceComponent() async {
        // typicalDeviceCount = 0 → guard fails → device component not added → no data → 0
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: 5, typicalDeviceCount: 0, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 0)
    }

    // MARK: DNS component

    @Test func dnsUnder50MsScoreIs100() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: 20,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // dns < 50ms → 20pts, maxTotal=20 → 100
        #expect(result.score == 100)
    }

    @Test func dns50MsScoreIs75() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: 50,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // dns 50ms → 50..<100 → 15pts, maxTotal=20 → Int(15/20*100) = 75
        #expect(result.score == 75)
    }

    @Test func dns300MsScoreIsZero() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: 300,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        // dns >= 300ms → 0pts → 0
        #expect(result.score == 0)
    }

    // MARK: Score details

    @Test func latencyIncludedInDetails() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 25, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.details["latency"] != nil)
    }

    @Test func packetLossIncludedInDetails() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.05, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.details["packetLoss"] != nil)
    }

    @Test func offlineResultContainsConnectivityDetail() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: false)
        let result = await service.calculateScore()
        #expect(result.details["connectivity"] == "Offline")
    }

    // MARK: Thread safety — update then immediately calculate

    @Test func updateAndCalculateAreConcurrentlySafe() async {
        let service = NetworkHealthScoreService()
        // Perform multiple updates and a final calculateScore; no crash = pass
        service.update(latencyMs: 10, packetLoss: 0.0, dnsResponseMs: 30,
                       deviceCount: 5, typicalDeviceCount: 5, isConnected: true)
        service.update(latencyMs: 50, packetLoss: 0.02, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score >= 0)
        #expect(result.score <= 100)
    }
}

// MARK: - NetworkHealthScoreService.grade Tests

// Grades: 90-100→A, 80-89→B, 70-79→C, 60-69→D, 0-59→F
// We derive scores from known latency/dns inputs and verify grade boundaries.
// Score derivation:
//   latency 25ms (only) → 35/35*100=100 → A
//   latency 30ms (only) → 30/35*100=85  → B
//   dns 50ms (only)     → 15/20*100=75  → C
//   latency 60ms (only) → 22/35*100=62  → D
//   latency 100ms(only) → 12/35*100=34  → F
//   no data             → 0             → F
//   latency 30ms + dns 20ms → Int(50/55*100)=90 → A (boundary 90)
//   latency 30ms + dns 50ms → Int(45/55*100)=81 → B

@Suite("NetworkHealthScoreService – grade thresholds")
struct NetworkHealthScoreGradeTests {

    // Parameterized: latency-only inputs that produce scores in each grade band.
    // latency 25ms → 100 (A), 30ms → 85 (B), 60ms → 62 (D), 100ms → 34 (F), 200ms → 0 (F)
    @Test(arguments: zip(
        [25.0, 30.0, 60.0, 100.0, 200.0],
        ["A", "B", "D", "F", "F"]
    ))
    func gradeMatchesLatencyInput(latencyMs: Double, expectedGrade: String) async {
        let service = NetworkHealthScoreService()
        service.update(
            latencyMs: latencyMs,
            packetLoss: nil,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: true
        )
        let result = await service.calculateScore()
        #expect(result.grade == expectedGrade,
                "Score \(result.score) expected grade \(expectedGrade) got \(result.grade)")
    }

    @Test func scoreExactly90IsGradeA() async {
        // latency 30ms (30pts/35max) + dns 20ms (20pts/20max) → total=50, max=55
        // Int(50/55*100) = Int(90.909) = 90 → A
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 30, packetLoss: nil, dnsResponseMs: 20,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 90)
        #expect(result.grade == "A")
    }

    @Test func scoreInEightiesIsGradeB() async {
        // latency 30ms (30pts) + dns 50ms (15pts) → total=45, max=55
        // Int(45/55*100) = Int(81.818) = 81 → B
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 30, packetLoss: nil, dnsResponseMs: 50,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 81)
        #expect(result.grade == "B")
    }

    @Test func scoreInSeventiesIsGradeC() async {
        // dns 50ms only → score=75 → C
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: nil, dnsResponseMs: 50,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 75)
        #expect(result.grade == "C")
    }

    @Test func scoreInSixtiesIsGradeD() async {
        // latency 60ms → score=62 → D
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 60, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 62)
        #expect(result.grade == "D")
    }

    @Test func scoreBelow60IsGradeF() async {
        // latency 100ms → score=34 → F
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 100, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score == 34)
        #expect(result.grade == "F")
    }

    @Test func scoreZeroIsGradeF() async {
        // no data → 0 → F
        let service = NetworkHealthScoreService()
        let result = await service.calculateScore()
        #expect(result.score == 0)
        #expect(result.grade == "F")
    }
}

// MARK: - NetworkHealthScoreService returned model fields

@Suite("NetworkHealthScoreService – NetworkHealthScore model fields")
struct NetworkHealthScoreModelFieldTests {

    @Test func latencyMsPropagatesToResult() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 42, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.latencyMs == 42)
    }

    @Test func packetLossPropagatesToResult() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.05, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.packetLoss == 0.05)
    }

    @Test func latencyMsNilWhenNotProvided() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: nil, packetLoss: 0.0, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.latencyMs == nil)
    }

    @Test func packetLossNilWhenNotProvided() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 25, packetLoss: nil, dnsResponseMs: nil,
                       deviceCount: nil, typicalDeviceCount: nil, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.packetLoss == nil)
    }

    @Test func scoreIsClampedToMax100() async {
        // Perfect input on all four components → score should not exceed 100
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 5, packetLoss: 0.0, dnsResponseMs: 10,
                       deviceCount: 10, typicalDeviceCount: 10, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score <= 100)
    }

    @Test func scoreIsAtLeastZero() async {
        let service = NetworkHealthScoreService()
        service.update(latencyMs: 500, packetLoss: 1.0, dnsResponseMs: 1000,
                       deviceCount: 1, typicalDeviceCount: 100, isConnected: true)
        let result = await service.calculateScore()
        #expect(result.score >= 0)
    }
}
