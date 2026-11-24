import Foundation
import Testing
@testable import NetMonitorCore

@Suite("Alert rules (#394)")
struct AlertRuleEngineTests {
    private let home = UUID()
    private var printer: AlertRuleSubject {
        AlertRuleSubject(
            name: "Office Printer", ipAddress: "10.0.0.40", macAddress: "AA:BB:CC:00:00:40",
            deviceType: .printer, maker: "Brother Industries", networkID: home
        )
    }

    private func event(_ kind: AlertRuleEvent.Kind, _ subject: AlertRuleSubject? = nil) -> AlertRuleEvent {
        AlertRuleEvent(kind: kind, subject: subject ?? printer)
    }

    @Test func triggerMustMatchTheEventKind() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Printer offline", trigger: .wentOffline)
        #expect(evaluator.evaluate([event(.cameOnline)], rules: [rule]).isEmpty)
        #expect(evaluator.evaluate([event(.wentOffline)], rules: [rule]).map(\.rule.id) == [rule.id])
    }

    @Test func eachTriggerKindMatchesItsEvent() {
        var evaluator = AlertRuleEvaluator()
        let rules = [
            AlertRule(name: "on", trigger: .cameOnline),
            AlertRule(name: "off", trigger: .wentOffline),
            AlertRule(name: "new", trigger: .firstSeen)
        ]
        let fired = evaluator.evaluate([event(.cameOnline), event(.wentOffline), event(.firstSeen)], rules: rules)
        #expect(fired.map(\.rule.name) == ["on", "off", "new"])
    }

    @Test func deviceConditionMatchesIPMACOrNameIgnoringCase() {
        for device in ["10.0.0.40", "aa:bb:cc:00:00:40", "office printer"] {
            #expect(AlertRuleEngine.conditionsMatch(AlertRuleConditions(device: device), printer), "\(device)")
        }
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(device: "10.0.0.41"), printer))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(device: "printer"), printer), "Exact match, not contains")
    }

    @Test func typeMakerAndNetworkConditions() {
        #expect(AlertRuleEngine.conditionsMatch(AlertRuleConditions(deviceType: .printer), printer))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(deviceType: .router), printer))
        #expect(AlertRuleEngine.conditionsMatch(AlertRuleConditions(maker: "brother"), printer))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(maker: "Canon"), printer))
        #expect(AlertRuleEngine.conditionsMatch(AlertRuleConditions(networkID: home), printer))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(networkID: UUID()), printer))
    }

    @Test func aConditionOnAnUnknownFieldDoesNotMatch() {
        let bare = AlertRuleSubject(name: "Router", ipAddress: "10.0.0.1")
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(deviceType: .router), bare))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(maker: "Netgear"), bare))
        #expect(AlertRuleEngine.conditionsMatch(AlertRuleConditions(device: "  "), bare), "A blank field means any")
    }

    @Test func allConditionsMustMatch() {
        let conditions = AlertRuleConditions(device: "10.0.0.40", deviceType: .router)
        #expect(!AlertRuleEngine.conditionsMatch(conditions, printer))
    }

    @Test func aDisabledRuleNeverFires() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "off", isEnabled: false, trigger: .wentOffline)
        #expect(evaluator.evaluate([event(.wentOffline)], rules: [rule]).isEmpty)
    }

    @Test func latencyFiresOnceOnCrossingAndRearmsAfterDroppingBelow() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "slow", trigger: .latencyAbove(milliseconds: 100))
        let readings: [Double] = [50, 150, 180, 90, 120]
        let fired = readings.map { evaluator.evaluate([event(.latency(milliseconds: $0))], rules: [rule]).count }
        #expect(fired == [0, 1, 0, 0, 1])
    }

    @Test func latencyStateIsPerDevice() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "slow", trigger: .latencyAbove(milliseconds: 100))
        let other = AlertRuleSubject(name: "NAS", ipAddress: "10.0.0.50")
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).count == 1)
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150), other)], rules: [rule]).count == 1)
    }

    @Test func latencyEventsDoNotTriggerStatusRules() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "off", trigger: .wentOffline)
        #expect(evaluator.evaluate([event(.latency(milliseconds: 999))], rules: [rule]).isEmpty)
    }

    @Test func rulesRoundTripThroughJSON() throws {
        let rules = [
            AlertRule(name: "slow", trigger: .latencyAbove(milliseconds: 250), conditions: AlertRuleConditions(device: "nas")),
            AlertRule(
                name: "printer", isEnabled: false, trigger: .wentOffline,
                conditions: AlertRuleConditions(deviceType: .printer, networkID: home)
            )
        ]
        let decoded = try JSONDecoder().decode([AlertRule].self, from: JSONEncoder().encode(rules))
        #expect(decoded == rules)
    }

    // MARK: - Review fixes (#415)

    @Test func changingARulesDefinitionClearsItsCrossingState() {
        var evaluator = AlertRuleEvaluator()
        var rule = AlertRule(name: "slow", trigger: .latencyAbove(milliseconds: 100))
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).count == 1)
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).isEmpty)

        rule.trigger = .latencyAbove(milliseconds: 120)
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).count == 1, "New threshold, fresh state")

        rule.conditions = AlertRuleConditions(deviceType: .printer)
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).count == 1, "New conditions, fresh state")

        rule.name = "renamed"
        #expect(evaluator.evaluate([event(.latency(milliseconds: 150))], rules: [rule]).isEmpty, "A rename keeps state")
    }

    @Test func aStateKeyKeepsTwoTargetsOnOneHostApart() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "slow", trigger: .latencyAbove(milliseconds: 100))
        let icmp = AlertRuleSubject(name: "Router ping", ipAddress: "10.0.0.1", monitoredTargetID: UUID())
        let https = AlertRuleSubject(name: "Router admin", ipAddress: "10.0.0.1", monitoredTargetID: UUID())
        func run(_ subject: AlertRuleSubject, _ ms: Double) -> Int {
            evaluator.evaluate([AlertRuleEvent(kind: .latency(milliseconds: ms), subject: subject)], rules: [rule]).count
        }

        #expect(run(icmp, 150) == 1)
        #expect(run(https, 50) == 0, "The HTTPS target dropping below doesn't re-arm the ICMP one")
        #expect(run(icmp, 150) == 0)
        #expect(run(https, 150) == 1, "Each target crosses on its own")
    }
}
