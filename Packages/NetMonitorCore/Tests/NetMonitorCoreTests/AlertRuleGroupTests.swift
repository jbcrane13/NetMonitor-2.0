import Foundation
import SwiftData
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

/// #615 review: a device's state is the best of its interfaces'. One interface going offline (or
/// coming back) while another answers is not the device going offline (or coming back).
@Suite("Alert rules judge a device by every interface")
struct AlertRuleDevicePresenceTests {
    let primary = UUID(), wifi = UUID(), group = UUID()

    func subject(_ row: UUID, anotherOnline: Bool) -> AlertRuleSubject {
        var subject = AlertRuleSubject(name: "Mac mini", ipAddress: "10.0.0.\(row == primary ? 10 : 40)", deviceID: row)
        subject.deviceGroupID = group
        subject.groupMemberIDs = [primary, wifi]
        subject.onlineInterfaceIDs = anotherOnline ? [row == primary ? wifi : primary] : []
        return subject
    }

    @Test("An interface going offline while another answers fires no offline rule; the last one does")
    func offlineNeedsEveryInterface() {
        let rule = AlertRule(name: "Mac offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: primary))
        var evaluator = AlertRuleEvaluator()
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject(primary, anotherOnline: true))], rules: [rule]).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .stillOffline, subject: subject(primary, anotherOnline: true))], rules: [rule]).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: subject(wifi, anotherOnline: false))], rules: [rule]).count == 1)
    }

    @Test("An interface coming back while another already answered is not the device coming online")
    func onlineOnlyFromOffline() {
        let rule = AlertRule(name: "Mac back", trigger: .cameOnline, conditions: AlertRuleConditions(deviceID: primary))
        var evaluator = AlertRuleEvaluator()
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: subject(wifi, anotherOnline: true))], rules: [rule]).isEmpty)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: subject(wifi, anotherOnline: false))], rules: [rule]).count == 1)
    }

    @Test("Both interfaces coming back in one scan is the device coming back: one alert")
    func simultaneousRecoveryAlertsOnce() {
        let rule = AlertRule(name: "Mac back", trigger: .cameOnline, conditions: AlertRuleConditions(deviceID: primary))
        var evaluator = AlertRuleEvaluator()
        // After the scan both are saved online, so each sees the other online.
        var wired = subject(primary, anotherOnline: false)
        wired.onlineInterfaceIDs = [wifi]
        var wireless = subject(wifi, anotherOnline: false)
        wireless.onlineInterfaceIDs = [primary]
        let matches = evaluator.evaluate(
            [AlertRuleEvent(kind: .cameOnline, subject: wired), AlertRuleEvent(kind: .cameOnline, subject: wireless)], rules: [rule]
        )
        #expect(matches.count == 1)
    }

    @Test("A device of one row is judged as before")
    func singleRowUnchanged() {
        let rule = AlertRule(name: "Printer offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: primary))
        var evaluator = AlertRuleEvaluator()
        let alone = AlertRuleSubject(name: "Printer", ipAddress: "10.0.0.9", deviceID: primary)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: alone)], rules: [rule]).count == 1)
    }
}

/// `setDevice` records whether another interface of the device is online, from the saved statuses.
@Suite("Rule subject from a device group")
@MainActor
struct AlertRuleSubjectGroupTests {
    @Test("Another interface online is read from the other members' saved status")
    func anotherInterfaceOnline() throws {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let wired = LocalDevice(ipAddress: "10.0.0.10", macAddress: "", status: .offline)
        let wifi = LocalDevice(ipAddress: "10.0.0.40", macAddress: "", status: .online)
        let group = UUID()
        for row in [wired, wifi] {
            context.insert(row)
            row.deviceGroupID = group
            row.groupPrimaryID = wired.id
        }
        let device = try #require(DeviceGroups.project([wired, wifi]).first)
        var subject = AlertRuleSubject(name: nil, ipAddress: wired.ipAddress)
        subject.setDevice(device, row: wired)
        #expect(subject.onlineInterfaceIDs == [wifi.id])
        var other = AlertRuleSubject(name: nil, ipAddress: wifi.ipAddress)
        other.setDevice(device, row: wifi)
        #expect(other.onlineInterfaceIDs.isEmpty, "the only other interface is offline")
    }
}

/// #619 review: an outage's state follows the device through grouping and separating, so a
/// recovery under a new identity ends it and a later outage alerts again.
@Suite("Alert rule outages across identity changes")
struct AlertRuleIdentityChangeTests {
    let alpha = UUID(), bravo = UUID(), group = UUID()

    func single(_ row: UUID) -> AlertRuleSubject {
        AlertRuleSubject(name: "Mac mini", ipAddress: "10.0.0.10", deviceID: row)
    }

    func grouped(_ row: UUID) -> AlertRuleSubject {
        var subject = single(row)
        subject.deviceGroupID = group
        subject.groupMemberIDs = [alpha, bravo]
        return subject
    }

    @Test("A device's outage, its recovery as a group, a split, then a second outage: the second alerts")
    func recoveryUnderAGroupEndsTheRowsOutage() {
        let rule = AlertRule(name: "Mac offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: alpha))
        var evaluator = AlertRuleEvaluator()
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: single(alpha))], rules: [rule]).count == 1)
        _ = evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: grouped(alpha))], rules: [rule])
        // Separated again: alpha is a device of one row.
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: single(alpha))], rules: [rule]).count == 1)
    }

    @Test("A group's outage ends when one of its rows comes back on its own, so the regrouped device alerts again")
    func recoveryOfAFormerMemberEndsTheGroupsOutage() {
        let rule = AlertRule(name: "Mac offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: alpha))
        var evaluator = AlertRuleEvaluator()
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: grouped(alpha))], rules: [rule]).count == 1)
        _ = evaluator.evaluate([AlertRuleEvent(kind: .cameOnline, subject: single(alpha))], rules: [rule])
        // Undo restores the same group ID.
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: grouped(alpha))], rules: [rule]).count == 1)
    }

    @Test("While a row's outage stands, the group it joins doesn't alert for it again")
    func anOpenOutageCoversTheNewIdentity() {
        let rule = AlertRule(name: "Mac offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: alpha))
        var evaluator = AlertRuleEvaluator()
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: single(alpha))], rules: [rule]).count == 1)
        #expect(evaluator.evaluate([AlertRuleEvent(kind: .wentOffline, subject: grouped(alpha))], rules: [rule]).isEmpty)
    }
}
