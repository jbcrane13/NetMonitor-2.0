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

    /// A failed HTTP check (a 503) is unreachable and still has a latency.
    @Test func aLatencyReadingFromAFailedCheckDoesNotRestartTheOfflineClock() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, minimumDuration: 300)
        let subject = nas(named: "NAS")
        let checks: [(AlertRuleEvent.Kind, TimeInterval)] = [(.wentOffline, 0), (.stillOffline, 150), (.stillOffline, 300), (.stillOffline, 450)]
        let fired = checks.map { kind, time in
            evaluator.evaluate(
                [AlertRuleEvent(kind: kind, subject: subject), AlertRuleEvent(kind: .latency(milliseconds: 40), subject: subject)],
                rules: [rule], now: at(time)
            ).count
        }
        #expect(fired == [0, 0, 1, 0])
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

    @Test func endingATargetsEpisodesRestartsItsClockAndLeavesScanTimedOnesAlone() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Slow 2 min", trigger: .latencyAbove(milliseconds: 250), minimumDuration: 120)
        let offline = AlertRule(name: "Down 5 min", trigger: .wentOffline, minimumDuration: 300)
        var target = nas(named: "NAS")
        target.monitoredTargetID = UUID()
        let high = AlertRuleEvent(kind: .latency(milliseconds: 300), subject: target)
        // Another device, timed by scans: no target checks it.
        let scanned = AlertRuleSubject(name: "Printer", ipAddress: "10.0.0.40", macAddress: "AA:BB:CC:00:00:40", deviceID: UUID())
        #expect(evaluator.evaluate([high], rules: [rule, offline], now: at(0)).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: scanned)], rules: [rule, offline], now: at(0)).isEmpty)

        evaluator.endMonitoredTargetEpisodes()

        // Ten unchecked minutes later, one high reading starts a new clock.
        #expect(evaluator.evaluate([high], rules: [rule, offline], now: at(600)).isEmpty)
        #expect(evaluator.evaluate([high], rules: [rule, offline], now: at(720)).map(\.rule.name) == ["Slow 2 min"])
        // The scan-timed outage kept its start.
        let still = AlertRuleEvent(kind: .stillOffline, subject: scanned)
        #expect(evaluator.evaluate([still], rules: [rule, offline], now: at(730)).map(\.rule.name) == ["Down 5 min"])
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

    // MARK: - One outage, one alert (#450 review)

    private func targetSubject(_ target: UUID) -> AlertRuleSubject {
        var subject = nas(named: "NAS")
        subject.monitoredTargetID = target
        return subject
    }

    @Test func aTargetAndAScanReportingTheSameOutageAlertOnce() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID), minimumDuration: 300)
        let target = targetSubject(UUID())
        var fired: [String] = []
        func run(_ kind: AlertRuleEvent.Kind, _ subject: AlertRuleSubject, at time: TimeInterval, since: Date? = nil) {
            let matches = evaluator.evaluate([AlertRuleEvent(kind: kind, subject: subject, offlineSince: since)], rules: [rule], now: at(time))
            fired += matches.map { $0.event.subject.monitoredTargetID == nil ? "scan" : "target" }
        }
        run(.wentOffline, target, at: 0)
        run(.stillOffline, target, at: 300)
        // The scan's grace period ends later in the same outage.
        run(.wentOffline, nas(named: "NAS"), at: 900, since: at(0))
        run(.stillOffline, target, at: 930)
        #expect(fired == ["target"])
    }

    @Test func withoutATargetTheScanStillTimesTheOutage() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID), minimumDuration: 300)
        let report = AlertRuleEvent(kind: .wentOffline, subject: nas(named: "NAS"), offlineSince: at(-900))
        #expect(evaluator.evaluate([report], rules: [rule], now: at(0)).count == 1)
    }

    @Test func onceMonitoringStopsScansTimeTheDeviceAgain() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID), minimumDuration: 300)
        _ = evaluator.evaluate([AlertRuleEvent(kind: .latency(milliseconds: 5), subject: targetSubject(UUID()))], rules: [rule], now: at(0))
        let report = AlertRuleEvent(kind: .wentOffline, subject: nas(named: "NAS"), offlineSince: at(100))
        #expect(evaluator.evaluate([report], rules: [rule], now: at(1000)).isEmpty, "A target checks the NAS")
        evaluator.endMonitoredTargetEpisodes()
        #expect(evaluator.evaluate([report], rules: [rule], now: at(1000)).count == 1)
    }

    /// A rule that names the device by text matches the scan's device name but not a target with
    /// another name. No target times that rule, so the scan's report must still fire it.
    @Test func aTargetThatDoesNotMatchARuleLeavesItsScanReportsAlone() {
        var evaluator = AlertRuleEvaluator()
        let byName = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(device: "Office NAS"),
                               minimumDuration: 300)
        let byID = AlertRule(name: "Down 5 min by ID", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID),
                             minimumDuration: 300)
        var target = targetSubject(UUID())
        target.name = "NAS ping"
        _ = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: target)], rules: [byName, byID], now: at(0))
        let report = AlertRuleEvent(kind: .wentOffline, subject: nas(named: "Office NAS"), offlineSince: at(0))
        let fired = evaluator.evaluate([report], rules: [byName, byID], now: at(900))
        #expect(fired.map(\.rule.name) == ["Down 5 min"], "The target times only the rule it matches")
    }

    /// Ping and HTTP targets on one device keep their own clocks: one recovering doesn't end the other's outage.
    @Test func twoTargetsOnOneDeviceKeepSeparateOutages() {
        var evaluator = AlertRuleEvaluator()
        let rule = AlertRule(name: "Down 5 min", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: nasID), minimumDuration: 300)
        let ping = targetSubject(UUID())
        let http = targetSubject(UUID())
        _ = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: ping), AlertRuleEvent(kind: .wentOffline, subject: http)],
                               rules: [rule], now: at(0))
        _ = evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: http)], rules: [rule], now: at(100))
        let fired = evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: ping)], rules: [rule], now: at(300))
        #expect(fired.map(\.event.subject.monitoredTargetID) == [ping.monitoredTargetID])
    }
}
