import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #594 (design v3.1 §8): a row keeps the last strong Bonjour host its address answered for, and
/// when. It is written only when the row answers with exactly one strong claim this scan.
@Suite("ScanReconciler Bonjour host evidence", .serialized)
@MainActor
final class ScanReconcilerBonjourHostTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "ScanReconcilerBonjourHostTests.\(UUID().uuidString)"

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    func reconcile(_ scan: [DiscoveredDevice], in context: ModelContext, at minutes: Double) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let time = start.addingTimeInterval(minutes * 60)
        try ScanReconciler(context: context, history: ScanHistory(defaults: defaults)).reconcile(
            scan, networkProfileID: home, scanDate: time, now: time
        )
    }

    func device(ip: String = "192.168.7.20", mac: String? = "AA:BB:CC:00:00:01", claims hosts: [String], cached: Bool = false) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: "Studio", vendor: nil, macAddress: mac, latency: 4, discoveredAt: start, source: .bonjour,
            networkProfileID: home, isCached: cached,
            bonjourClaims: hosts.map { HostClaim(host: $0, service: "Studio", address: ip) }
        )
    }

    func row(_ context: ModelContext) throws -> LocalDevice {
        try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
    }

    @Test("One strong claim is stored with the scan time; a different one replaces it")
    func storesAndReplaces() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        try reconcile([device(claims: ["studio.local"])], in: context, at: 0)
        #expect(try row(context).bonjourHost == "studio.local")
        #expect(try row(context).bonjourHostSeenAt == start)
        try reconcile([device(claims: ["studio-2.local"])], in: context, at: 10)
        #expect(try row(context).bonjourHost == "studio-2.local")
        #expect(try row(context).bonjourHostSeenAt == start.addingTimeInterval(600))
    }

    @Test("Answering with no claim keeps the host and doesn't advance its time")
    func noClaimKeeps() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        try reconcile([device(claims: ["studio.local"])], in: context, at: 0)
        try reconcile([device(claims: [])], in: context, at: 10)
        #expect(try row(context).bonjourHost == "studio.local")
        #expect(try row(context).bonjourHostSeenAt == start)
    }

    @Test("Conflicting strong claims, a generic claim or a cached sighting write nothing", arguments: [
        (["studio.local", "office.local"], false), (["iphone.local"], false), (["studio.local"], true)
    ])
    func ambiguousWritesNothing(hosts: [String], cached: Bool) throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        try reconcile([device(claims: [])], in: context, at: 0)
        try reconcile([device(claims: hosts, cached: cached), device(ip: "192.168.7.99", mac: nil, claims: [])], in: context, at: 10)
        #expect(try row(context).bonjourHost == nil)
        #expect(try row(context).bonjourHostSeenAt == nil)
    }

    @Test("Two observations of one MAC pool their claims before deduplication, so a conflict is seen")
    func onePerMACPoolsClaims() throws {
        let (container, context) = try makeContext()
        defer { withExtendedLifetime(container) {} }
        let scan = [device(ip: "192.168.7.20", claims: ["studio.local"]), device(ip: "192.168.7.21", claims: ["office.local"])]
        try reconcile(scan, in: context, at: 0)
        #expect(try row(context).bonjourHost == nil)
        let kept = PresenceMatch.onePerMAC(scan)
        #expect(kept.count == 1)
        #expect(Set(kept[0].bonjourClaims.map(\.host)) == ["studio.local", "office.local"])
    }
}
