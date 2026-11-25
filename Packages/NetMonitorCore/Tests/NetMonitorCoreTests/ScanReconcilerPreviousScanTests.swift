import Testing
import Foundation
import SwiftData
import NetworkScanKit
@testable import NetMonitorCore

/// Lead, 2026-11-25: for an address-only match with an unknown name, a row the network's previous
/// recorded scan saw counts as recent, however far apart scans are (#596).
extension ScanReconcilerTests {
    /// Lead, 2026-11-25: a row the network's previous recorded scan saw never missed a scan, so a
    /// nameless device keeps it however far apart scans are. Hourly auto-scan: one row over 5 scans.
    @Test func hourlyScansKeepANamelessDeviceOnOneRow() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        for hour in 0..<5 {
            let time = minutes(Double(hour) * 60)
            try reconciler.reconcile([device(ip: "192.168.7.28", mac: nil, name: nil)], networkProfileID: home, scanDate: time, now: time)
        }
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved.first?.status == .online)
        #expect(saved.first?.lastSeen == minutes(240))
    }

    /// The Mac slept under 2 hours (`previousScanReach`); the scan before it saw the device, so it
    /// keeps its row.
    @Test func aNamelessDeviceKeepsItsRowAcrossAShortSleepWhenThePreviousScanSawIt() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.29", mac: nil, name: nil)], networkProfileID: home, scanDate: start, now: start)
        let row = try #require(try rows(context).first)
        row.notes = "Printer"
        try reconciler.reconcile([device(ip: "192.168.7.29", mac: nil, name: nil)], networkProfileID: home, scanDate: minutes(110), now: minutes(110))
        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved.first?.id == row.id)
        #expect(saved.first?.notes == "Printer")
    }

    /// Lead's cap: four days later the address may belong to another device; a nameless device
    /// there gets a new row even though the previous scan, days ago, saw the old one.
    @Test func aPreviousScanDaysAgoDoesNotCount() throws {
        let (container, context) = try makeContext()
        _ = container
        let reconciler = try makeReconciler(context)
        try reconciler.reconcile([device(ip: "192.168.7.30", mac: nil, name: nil)], networkProfileID: home, scanDate: start, now: start)
        let old = try #require(try rows(context).first)
        old.notes = "Old camera"
        let later = minutes(4 * 24 * 60)
        try reconciler.reconcile([device(ip: "192.168.7.30", mac: nil, name: nil)], networkProfileID: home, scanDate: later, now: later)
        let saved = try rows(context)
        #expect(saved.count == 2)
        #expect(old.lastSeen == start)
        #expect(old.notes == "Old camera")
    }

    @Test func theRowThePreviousScanSawCountsAsRecent() {
        let previous = minutes(60)
        let seen = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.42", macAddress: nil, name: nil), lastSeen: previous)
        let missed = PresenceMatch.Known(DeviceMatchCandidate(ipAddress: "192.168.7.43", macAddress: nil, name: nil), lastSeen: start)
        let observed = [
            DeviceMatchCandidate(ipAddress: "192.168.7.42", macAddress: nil, name: nil),
            DeviceMatchCandidate(ipAddress: "192.168.7.43", macAddress: nil, name: nil)
        ]
        let assignment = PresenceMatch.assign(known: [seen, missed], observed: observed, now: minutes(120), window: 15 * 60, previousScan: previous)
        #expect(assignment == [0, nil])
        // Past the reach, only the grace window counts.
        let late = PresenceMatch.assign(
            known: [seen, missed], observed: observed, now: previous.addingTimeInterval(PresenceMatch.previousScanReach + 60),
            window: 15 * 60, previousScan: previous
        )
        #expect(late == [nil, nil])
    }

    /// Review (#601): a failed read of the rows saves nothing and records nothing; the same scan
    /// applies once the store answers.
    @Test func aFailedFetchSavesNothingAndTheSameScanAppliesLater() throws {
        let (container, context) = try makeContext()
        _ = container
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        struct StoreUnavailable: Error {}
        let failing = ScanReconciler(context: context, history: ScanHistory(defaults: defaults), fetch: { _ in throw StoreUnavailable() })
        #expect(throws: StoreUnavailable.self) {
            try failing.reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        }
        #expect(try rows(context).isEmpty)
        let outcome = try makeReconciler(context).reconcile([scanned(0)], networkProfileID: home, scanDate: start, now: start)
        #expect(outcome != .skipped)
        #expect(try rows(context).count == 1)
    }

    /// The tracker forgets misses counted before a new owner of the grace count (#596).
    @Test @MainActor func forgettingMissesRestartsTheGraceCountButKeepsOfflineDevices() {
        let suite = "forgetMisses.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = DeviceChangeTracker(defaults: defaults)
        let router = DeviceObservation(ipAddress: "192.168.7.1", macAddress: "AC:DE:48:00:00:01", name: "router")
        let printer = DeviceObservation(ipAddress: "192.168.7.20", macAddress: "AC:DE:48:00:00:20", name: "printer")
        _ = tracker.record(scope: "home", observed: [router, printer], now: start)
        _ = tracker.record(scope: "home", observed: [router], now: minutes(10))
        _ = tracker.record(scope: "home", observed: [router], now: minutes(20))
        tracker.forgetMisses(for: "home")
        // Without forgetting, this third miss past 15 minutes would report the printer left.
        let events = tracker.record(scope: "home", observed: [router], now: minutes(30))
        #expect(!events.contains {
            if case .wentOffline = $0 {
                true
            } else {
                false
            }
        })
        let later = [40.0, 50].flatMap { tracker.record(scope: "home", observed: [router], now: minutes($0)) }
        #expect(later.contains {
            if case .wentOffline(let known) = $0 {
                known.name == "printer"
            } else {
                false
            }
        })
    }
}
