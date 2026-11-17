import Foundation
import Testing
@testable import NetMonitorCore

@Suite("DeviceChangeDetector (#393)")
@MainActor
struct DeviceChangeDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let policy = DeviceGracePolicy(missedScans: 3, interval: 15 * 60)

    private func obs(_ ip: String, _ mac: String?, _ name: String? = nil, cached: Bool = false) -> DeviceObservation {
        DeviceObservation(ipAddress: ip, macAddress: mac, name: name, isCached: cached)
    }

    /// Runs scans 5 minutes apart and returns each scan's events.
    private func run(_ scans: [[DeviceObservation]], from known: [KnownDevice] = [], step: TimeInterval = 300) -> [[DeviceChangeEvent]] {
        var state = known
        var all: [[DeviceChangeEvent]] = []
        for (index, scan) in scans.enumerated() {
            let result = DeviceChangeDetector.detect(
                known: state, observed: scan, now: start.addingTimeInterval(Double(index) * step), policy: policy
            )
            state = result.known
            all.append(result.events)
        }
        return all
    }

    private let phone = "AA:BB:CC:00:00:01"
    private let laptop = "AA:BB:CC:00:00:02"

    @Test func firstScanIsABaseline() {
        let events = run([[obs("10.0.0.2", phone), obs("10.0.0.3", laptop)]])
        #expect(events == [[]])
    }

    @Test func aTrulyNewDeviceIsReportedOnce() {
        let newcomer = obs("10.0.0.9", "AA:BB:CC:00:00:09", "tv")
        let events = run([
            [obs("10.0.0.2", phone)],
            [obs("10.0.0.2", phone), newcomer],
            [obs("10.0.0.2", phone), newcomer]
        ])
        #expect(events == [[], [.firstSeen(newcomer)], []])
    }

    @Test func aSleepingDeviceThatReturnsIsNotNew() {
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)]
        ])
        #expect(events == [[], [], []])
    }

    @Test func goesOfflineOnlyAfterTheGracePeriodThenComesBackOnline() {
        let base = [obs("10.0.0.2", phone), obs("10.0.0.3", laptop, "laptop")]
        let onlyPhone = [obs("10.0.0.2", phone)]
        // Scans 1–3 miss the laptop; by scan 3 it has missed 3 scans over 15 minutes.
        let events = run([base, onlyPhone, onlyPhone, onlyPhone, onlyPhone, base], step: 300)
        #expect(events[1].isEmpty)
        #expect(events[2].isEmpty)
        guard case let .wentOffline(gone)? = events[3].first else {
            Issue.record("expected wentOffline at scan 3, got \(events)")
            return
        }
        #expect(gone.macAddress == laptop)
        #expect(events[4].isEmpty, "Offline is reported once")
        #expect(events[5] == [.cameOnline(obs("10.0.0.3", laptop, "laptop"))])
    }

    @Test func oneMissedScanIsNeverEnoughEvenAnHourApart() {
        let events = run([[obs("10.0.0.2", phone), obs("10.0.0.3", laptop)], [obs("10.0.0.2", phone)]], step: 3600)
        #expect(events[1].isEmpty)
    }

    @Test func missedScansAloneAreNotEnoughWithinTheInterval() {
        let onlyPhone = [obs("10.0.0.2", phone)]
        let events = run([[obs("10.0.0.2", phone), obs("10.0.0.3", laptop)], onlyPhone, onlyPhone, onlyPhone, onlyPhone], step: 60)
        #expect(events.allSatisfy { $0.isEmpty }, "4 scans in 4 minutes is under the 15-minute grace")
    }

    @Test func anIPChangeIsReportedAsChanged() {
        let events = run([[obs("10.0.0.2", phone, "phone")], [obs("10.0.0.7", phone, "phone")]])
        guard case let .changed(now, previous)? = events[1].first else {
            Issue.record("expected changed, got \(events)")
            return
        }
        #expect(events[1].count == 1)
        #expect(previous.ipAddress == "10.0.0.2")
        #expect(now.ipAddress == "10.0.0.7")
    }

    @Test func aNameAppearingIsEnrichmentButARenameIsAChange() {
        let events = run([
            [obs("10.0.0.2", phone)],
            [obs("10.0.0.2", phone, "phone")],
            [obs("10.0.0.2", phone, "kitchen-phone")]
        ])
        #expect(events[1].isEmpty)
        #expect(events[2].count == 1)
        if case .changed = events[2].first {} else {
            Issue.record("expected changed, got \(events[2])")
        }
    }

    @Test func aRotatedPrivateAddressWithTheSameIPAndNameIsNotNew() {
        let oldPrivate = "3A:11:22:33:44:55"
        let newPrivate = "7E:66:77:88:99:00"
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.20", oldPrivate, "iPhone")],
            [obs("10.0.0.2", phone), obs("10.0.0.20", newPrivate, "iPhone")]
        ])
        #expect(events[1].isEmpty)
    }

    @Test func aPrivateAddressMatchingOnlyByIPIsNew() {
        let newPrivate = "7E:66:77:88:99:00"
        let newcomer = obs("10.0.0.20", newPrivate, "Pixel")
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.20", "3A:11:22:33:44:55", "iPhone")],
            [obs("10.0.0.2", phone), newcomer]
        ])
        #expect(events[1] == [.firstSeen(newcomer)], "Same IP, different name: DHCP reuse, not a rotation")
    }

    @Test func aCachedOnlyDeviceAlertsOnceWhenItFirstAnswers() {
        let stranger = "AA:BB:CC:00:00:77"
        let answered = obs("10.0.0.77", stranger)
        let events = run([
            [obs("10.0.0.2", phone)],
            [obs("10.0.0.2", phone), obs("10.0.0.77", stranger, cached: true)],
            [obs("10.0.0.2", phone), answered],
            [obs("10.0.0.2", phone), answered]
        ])
        #expect(events == [[], [], [.firstSeen(answered)], []])
    }

    @Test func theIOSPlaceholderAddressIsNotAnIdentity() {
        let placeholder = "02:00:00:00:00:00"
        let first = obs("10.0.0.5", placeholder)
        let second = obs("10.0.0.6", placeholder)
        let events = run([[obs("10.0.0.2", phone)], [obs("10.0.0.2", phone), first, second]])
        #expect(events[1] == [.firstSeen(first), .firstSeen(second)], "Two placeholder devices stay two devices")
    }

    @Test func macAddressCaseDoesNotSplitADevice() {
        let events = run([[obs("10.0.0.2", "aa:bb:cc:00:00:01")], [obs("10.0.0.2", "AA:BB:CC:00:00:01")]])
        #expect(events == [[], []])
    }

    @Test func trackerSeedsAnUnstoredScopeSoAnUpgradeIsNotABurstOfNewDevices() {
        let suite = "DeviceChangeDetectorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = DeviceChangeTracker(defaults: defaults)
        let events = tracker.record(scope: "net", observed: [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)], now: start) {
            [KnownDevice(macAddress: phone, ipAddress: "10.0.0.2", name: nil, firstSeen: start, lastSeen: start),
             KnownDevice(macAddress: laptop, ipAddress: "10.0.0.3", name: nil, firstSeen: start, lastSeen: start)]
        }
        #expect(events.isEmpty)
        #expect(tracker.hasState(for: "net"))
    }

    // MARK: - Identity transitions (#410 review)

    @Test func aKnownDeviceReturningWithoutItsMACIsNotNew() {
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", nil)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", nil)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", nil)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", nil)]
        ])
        #expect(events.allSatisfy { $0.isEmpty }, "Same device, MAC unreadable: no new, no offline")
    }

    @Test func anIPKeyedDeviceGainingAPublicMACIsNotNewAndNeverGoesOffline() {
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.3", nil)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)]
        ])
        #expect(events.allSatisfy { $0.isEmpty }, "The IP-keyed record becomes the MAC record")
    }

    @Test func noReconcileWhenTheCandidateWasItselfSeenThisScan() {
        let newcomer = obs("10.0.0.3", nil)
        // The laptop answers with its MAC at .3, and a MAC-less device also shows at .3.
        let events = run([
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop)],
            [obs("10.0.0.2", phone), obs("10.0.0.3", laptop), newcomer]
        ])
        #expect(events[1] == [.firstSeen(newcomer)])
    }

    // MARK: - Retention (#410 review)

    @Test func unconfirmedDevicesExpireButConfirmedOnesAreKept() {
        let day: TimeInterval = 86400
        let first = DeviceChangeDetector.detect(
            known: [], observed: [obs("10.0.0.2", phone), obs("10.0.0.9", "AA:BB:CC:00:00:09", cached: true)],
            now: start, policy: policy
        )
        #expect(first.known.count == 2)

        let later = DeviceChangeDetector.detect(
            known: first.known, observed: [], now: start.addingTimeInterval(31 * day), policy: policy
        )
        #expect(later.known.map(\.macAddress) == [phone], "The cached-only entry expired; the phone is kept")
    }

    @Test func trackerDropsScopesForNetworksNoLongerKnown() {
        let suite = "DeviceChangeDetectorTests.scopes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = DeviceChangeTracker(defaults: defaults)
        _ = tracker.record(scope: "old", observed: [obs("10.0.0.2", phone)], now: start)
        _ = tracker.record(scope: "kept", observed: [obs("10.0.0.2", phone)], now: start)

        _ = tracker.record(scope: "current", observed: [obs("10.0.0.2", phone)], now: start, knownScopes: ["kept"])

        #expect(!tracker.hasState(for: "old"))
        #expect(tracker.hasState(for: "kept"))
        #expect(tracker.hasState(for: "current"), "The scanned network is always kept")
    }
}
