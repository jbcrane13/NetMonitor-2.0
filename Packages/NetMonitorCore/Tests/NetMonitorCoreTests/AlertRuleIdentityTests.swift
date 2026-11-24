import Foundation
import Testing
@testable import NetMonitorCore

@Suite("Alert rules: stable device identity and duration (#450)")
struct AlertRuleIdentityTests {
    private let nasID = UUID()

    private func nas(named name: String, id: UUID? = nil) -> AlertRuleSubject {
        AlertRuleSubject(name: name, ipAddress: "10.0.0.50", macAddress: "AA:BB:CC:00:00:50", deviceType: .storage, deviceID: id ?? nasID)
    }

    /// Rules saved before #450, exactly as the shipped encoder wrote them.
    @Test func rulesSavedBeforeTheIdentityFieldStillDecode() throws {
        let saved = """
        [{"conditions":{"device":"Office Printer","deviceType":"printer"},"id":"00000450-0000-4000-8000-000000000001",\
        "isEnabled":true,"name":"Printer offline","trigger":{"wentOffline":{}}},{"conditions":{},\
        "id":"00000450-0000-4000-8000-000000000002","isEnabled":false,"name":"Slow","trigger":{"latencyAbove":{"milliseconds":250}}}]
        """
        let rules = try JSONDecoder().decode([AlertRule].self, from: Data(saved.utf8))
        #expect(rules.count == 2)
        #expect(rules[0].name == "Printer offline")
        #expect(rules[0].trigger == .wentOffline)
        #expect(rules[0].conditions.device == "Office Printer")
        #expect(rules[0].conditions.deviceType == .printer)
        #expect(rules[0].conditions.deviceID == nil)
        #expect(rules[0].minimumDuration == nil)
        #expect(rules[1].trigger == .latencyAbove(milliseconds: 250))
        #expect(rules[1].isEnabled == false)
    }

    @Test func aRuleOnADeviceIDStillMatchesAfterTheDeviceIsRenamed() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID))
        let before = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: nas(named: "Synology DS920"))], rules: [rule])
        let after = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: nas(named: "Basement NAS"))], rules: [rule])
        #expect(before.map(\.rule.id) == [rule.id])
        #expect(after.map(\.rule.id) == [rule.id])
    }

    @Test func theDeviceIDWinsOverTheDeviceText() {
        let conditions = AlertRuleConditions(device: "Old Name", deviceID: nasID)
        #expect(AlertRuleEngine.conditionsMatch(conditions, nas(named: "New Name")))
        #expect(!AlertRuleEngine.conditionsMatch(conditions, nas(named: "Old Name", id: UUID())), "Another device with the old name")
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(deviceID: nasID), AlertRuleSubject(name: "x", ipAddress: "10.0.0.50")),
                "A subject with no known device")
    }

    // MARK: - Minimum duration

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func anOfflineRuleWithADurationFiresOnceTheDeviceHasBeenDownThatLong() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID), minimumDuration: 300)
        let subject = nas(named: "NAS")
        let checks: [(AlertRuleEvent.Kind, TimeInterval)] = [
            (.wentOffline, 0), (.stillOffline, 120), (.stillOffline, 299), (.stillOffline, 300), (.stillOffline, 420)
        ]
        let fired = checks.map { kind, time in
            evaluator.evaluate([AlertRuleEvent(kind: kind, subject: subject)], rules: [rule], now: at(time)).count
        }
        #expect(fired == [0, 0, 0, 1, 0])
    }

    @Test func comingBackOnlineRestartsTheDurationClock() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, minimumDuration: 300)
        let subject = nas(named: "NAS")
        let checks: [(AlertRuleEvent.Kind, TimeInterval)] = [
            (.wentOffline, 0), (.stillOffline, 200), (.cameOnline, 250), (.wentOffline, 260), (.stillOffline, 500), (.stillOffline, 560)
        ]
        let fired = checks.map { kind, time in
            evaluator.evaluate([AlertRuleEvent(kind: kind, subject: subject)], rules: [rule], now: at(time)).count
        }
        #expect(fired == [0, 0, 0, 0, 0, 1])
    }

    @Test func aScanThatReportsADeviceOfflineCountsFromWhenItWasLastSeen() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, minimumDuration: 300)
        // Scans report offline only after the grace period, so the device was last seen 15 minutes ago.
        let scanReport = AlertRuleEvent(kind: .wentOffline, subject: nas(named: "NAS"), offlineSince: at(-900))
        #expect(evaluator.evaluate([scanReport], rules: [rule], now: at(0)).count == 1)
        let longer = AlertRule(name: "Down 1 h", trigger: .wentOffline, minimumDuration: 3600)
        var other = AlertRuleEvaluator()
        #expect(other.evaluate([scanReport], rules: [longer], now: at(0)).isEmpty)
    }

    @Test func aStillOfflineCheckNeverFiresARuleWithoutADuration() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Offline", trigger: .wentOffline)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: nas(named: "NAS"))], rules: [rule]).isEmpty)
    }

    @Test func aLatencyRuleWithADurationFiresWhenLatencyStaysHighThatLong() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Slow 2 min", trigger: .latencyAbove(milliseconds: 250), minimumDuration: 120)
        let subject = nas(named: "NAS")
        let readings: [(Double, TimeInterval)] = [(300, 0), (310, 60), (100, 90), (300, 100), (320, 200), (330, 220), (340, 400)]
        let fired = readings.map { milliseconds, time in
            evaluator.evaluate([AlertRuleEvent(kind: .latency(milliseconds: milliseconds), subject: subject)], rules: [rule], now: at(time)).count
        }
        #expect(fired == [0, 0, 0, 0, 0, 1, 0])
    }

    @Test func changingARulesDurationForgetsItsTimers() {
        var evaluator = AlertRuleEvaluator()
        var rule = AlertRule(name: "Down", trigger: .wentOffline, minimumDuration: 300)
        let subject = nas(named: "NAS")
        _ = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject)], rules: [rule], now: at(0))
        rule.minimumDuration = 600
        // The clock restarts at the first check after the change.
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: subject)], rules: [rule], now: at(400)).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: subject)], rules: [rule], now: at(900)).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: subject)], rules: [rule], now: at(1000)).count == 1)
    }
}
