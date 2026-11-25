import Foundation
import Testing
@testable import NetMonitorCore

/// #594: a rule naming a device fires for any of its interfaces, once per outage of the device.
@Suite("Alert rules on device groups")
struct AlertRuleGroupTests {
    let primary = UUID(), wifi = UUID(), group = UUID(), other = UUID()

    func subject(_ row: UUID, grouped: Bool = true) -> AlertRuleSubject {
        var subject = AlertRuleSubject(name: "Mac mini", ipAddress: "10.0.0.\(row == primary ? 10 : 40)", deviceID: row)
        if grouped {
            subject.deviceGroupID = group
            subject.groupMemberIDs = [primary, wifi]
        }
        return subject
    }

    @Test("A rule naming the primary row matches the other interface, and not another device")
    func matchesAnyMember() {
        let conditions = AlertRuleConditions(deviceID: primary)
        #expect(AlertRuleEngine.conditionsMatch(conditions, subject(wifi)))
        #expect(AlertRuleEngine.conditionsMatch(conditions, subject(primary)))
        #expect(!AlertRuleEngine.conditionsMatch(conditions, subject(other, grouped: false)))
        #expect(!AlertRuleEngine.conditionsMatch(AlertRuleConditions(deviceID: wifi), subject(primary, grouped: false)))
    }

    @Test("Both interfaces going offline alert once for the device's outage")
    func oneAlertPerOutage() {
        let rule = AlertRule(name: "Mac offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: primary))
        var evaluator = AlertRuleEvaluator()
        let first = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject(primary))], rules: [rule])
        let second = evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject(wifi))], rules: [rule])
        #expect(first.count == 1)
        #expect(second.isEmpty)
        _ = evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: subject(wifi))], rules: [rule])
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject(primary))], rules: [rule]).count == 1)
    }
}
