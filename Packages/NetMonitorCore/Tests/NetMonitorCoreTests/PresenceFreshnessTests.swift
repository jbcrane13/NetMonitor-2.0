import Testing
import Foundation
@testable import NetMonitorCore

/// #583: what a saved row's status means now, from the network's last scan.
@Suite("PresenceFreshness")
struct PresenceFreshnessTests {
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let policy = DeviceGracePolicy()

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    @Test func aRowThatAnsweredARecentScanIsOnline() {
        let state = PresenceFreshness.of(status: .online, lastScan: scan, now: scan + minutes(5), policy: policy)
        #expect(state == .online)
    }

    @Test func aRowOnANetworkWithNoScanIsNotCheckedRecently() {
        let state = PresenceFreshness.of(status: .online, lastScan: nil, now: scan, policy: policy)
        #expect(state == .notCheckedRecently)
    }

    @Test func anOldScanMakesEveryRowNotCheckedRecentlyWhateverItsSavedStatus() {
        for status in DeviceStatus.allCases {
            let state = PresenceFreshness.of(status: status, lastScan: scan, now: scan + minutes(16), policy: policy)
            #expect(state == .notCheckedRecently, "status \(status)")
        }
    }

    @Test func aScanExactlyTheGraceIntervalOldIsStillRecent() {
        let atBoundary = PresenceFreshness.of(status: .online, lastScan: scan, now: scan + policy.interval, policy: policy)
        let past = PresenceFreshness.of(status: .online, lastScan: scan, now: scan + policy.interval + 1, policy: policy)
        #expect(atBoundary == .online)
        #expect(past == .notCheckedRecently)
    }

    @Test func aRowMarkedOfflineOnARecentlyScannedNetworkIsOffline() {
        let state = PresenceFreshness.of(status: .offline, lastScan: scan, now: scan, policy: policy)
        #expect(state == .offline)
    }

    /// Lead decision on #583: grace exists so a phone or sleeping laptop that misses a scan doesn't
    /// flap, so such a row reads Online; its line shows the real last-seen time, never "now".
    @Test func aRowWithinGraceThatMissedTheLastScanReadsOnlineWithItsLastSeen() {
        for status in [DeviceStatus.online, .cached, .idle] {
            let state = PresenceFreshness.of(status: status, lastScan: scan, now: scan, policy: policy)
            #expect(state == .online, "status \(status)")
        }
        #expect(PresenceFreshness.lastSeenText(since: scan - minutes(6), now: scan) == "Last seen 6 min ago")
    }

    @Test func aScanDatedUpToFiveMinutesAheadOfNowByClockSkewIsRecent() {
        #expect(PresenceFreshness.clockSkewAllowance == minutes(5))
        #expect(PresenceFreshness.of(status: .online, lastScan: scan, now: scan - minutes(5), policy: policy) == .online)
    }

    /// A scan further ahead is a wrong clock, not a recent check.
    @Test func aScanDatedMoreThanFiveMinutesAheadOfNowIsNotRecent() {
        #expect(PresenceFreshness.of(status: .online, lastScan: scan, now: scan - minutes(5) - 1, policy: policy) == .notCheckedRecently)
        #expect(PresenceFreshness.of(status: .online, lastScan: scan, now: scan - minutes(30), policy: policy) == .notCheckedRecently)
    }

    @Test func onlyOnlineIsOnline() {
        #expect(PresenceFreshness.online.isOnline)
        #expect(!PresenceFreshness.offline.isOnline)
        #expect(!PresenceFreshness.notCheckedRecently.isOnline)
    }

    @Test func everyStateHasItsOwnTextLabel() {
        let labels = PresenceFreshness.allCases.map(\.label)
        #expect(labels == ["Online", "Not checked recently", "Offline"])
    }
}

@Suite("PresenceFreshness past devices and wording")
struct PresenceFreshnessPastTests {
    private let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86400

    @Test func pastDevicesAreThoseUnseenForSevenDaysBeforeTheNetworksLastScan() {
        #expect(PresenceFreshness.pastDeviceDays == 7)
        #expect(PresenceFreshness.pastDeviceAge == 7 * day)
        #expect(PresenceFreshness.isPast(lastSeen: scan - 7 * day, lastScan: scan, now: scan))
        #expect(!PresenceFreshness.isPast(lastSeen: scan - 7 * day + 1, lastScan: scan, now: scan))
    }

    /// Not scanning for a week doesn't hide the whole list: age counts up to the last scan.
    @Test func aNetworkNotScannedForAWeekHidesNothingNew() {
        #expect(!PresenceFreshness.isPast(lastSeen: scan, lastScan: scan, now: scan + 30 * day))
    }

    @Test func withoutAScanAgeCountsToNow() {
        #expect(PresenceFreshness.isPast(lastSeen: scan, lastScan: nil, now: scan + 8 * day))
        #expect(!PresenceFreshness.isPast(lastSeen: scan, lastScan: nil, now: scan + 6 * day))
    }

    @Test func aLastSeenInTheFutureIsNeverPast() {
        #expect(!PresenceFreshness.isPast(lastSeen: scan + day, lastScan: scan, now: scan))
    }

    @Test func lastSeenReadsAsRelativeTime() {
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 20) == "Last seen just now")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 60) == "Last seen 1 min ago")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 5 * 60 + 59) == "Last seen 5 min ago")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 3600) == "Last seen 1 hour ago")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 3 * 3600) == "Last seen 3 hours ago")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + day) == "Last seen 1 day ago")
        #expect(PresenceFreshness.lastSeenText(since: scan, now: scan + 2 * day + 5) == "Last seen 2 days ago")
    }

    @Test func aLastSeenInTheFutureReadsAsJustNow() {
        #expect(PresenceFreshness.lastSeenText(since: scan + 600, now: scan) == "Last seen just now")
    }

    @Test func aRowSaysItsStateAndLastSeenOnceForVoiceOver() {
        let home = UUID()
        let row = LocalDevice(ipAddress: "192.168.1.9", macAddress: "", status: .offline, networkProfileID: home)
        row.lastSeen = scan - 30 * 60
        let presence = PresenceSnapshot(lastScans: [home: scan], now: scan)
        #expect(presence.statusText(row) == "Offline · Last seen 30 min ago")
        #expect(presence.accessibilityText(row) == "Offline, last seen 30 min ago")
        #expect(presence.relativeLastSeen(row) == "30 min ago")
        #expect(presence.isNetworkChecked(home))
        #expect(!presence.isNetworkChecked(nil))
    }

    /// The companion feed's sighting (#598): only a device that answered the latest recent scan.
    @Test func onlyADeviceThatAnsweredTheLatestRecentScanCountsAsAnswering() {
        let home = UUID()
        func row(_ status: DeviceStatus, seen: Date) -> LocalDevice {
            let row = LocalDevice(ipAddress: "192.168.1.9", macAddress: "", status: status, networkProfileID: home)
            row.lastSeen = seen
            return row
        }
        let presence = PresenceSnapshot(lastScans: [home: scan], now: scan + 60)
        #expect(presence.answeredLatestScan(row(.online, seen: scan)))
        #expect(!presence.answeredLatestScan(row(.cached, seen: scan - 600)), "only the ARP cache listed it")
        #expect(!presence.answeredLatestScan(row(.online, seen: scan - 600)), "within grace, but missed the scan")
        #expect(!presence.answeredLatestScan(row(.offline, seen: scan - 3600)))
        let stale = PresenceSnapshot(lastScans: [home: scan], now: scan + 3600)
        #expect(!stale.answeredLatestScan(row(.online, seen: scan)), "the scan is old")
    }

    @Test func aLatencyIsShownOnlyWhileTheDeviceIsOnline() {
        let home = UUID()
        let row = LocalDevice(ipAddress: "192.168.1.9", macAddress: "", status: .online, lastLatency: 4, networkProfileID: home)
        #expect(PresenceSnapshot(lastScans: [home: scan], now: scan).currentLatency(row) == 4)
        #expect(PresenceSnapshot(lastScans: [home: scan], now: scan + 3600).currentLatency(row) == nil, "not checked recently")
        row.status = .offline
        #expect(PresenceSnapshot(lastScans: [home: scan], now: scan).currentLatency(row) == nil, "offline")
    }
}
