import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

// MARK: - Helpers

@MainActor
private final class FakeNotificationPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    var categories: [String] { requests.map(\.content.categoryIdentifier) }
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

private func makeDefaults() -> (UserDefaults, String) {
    let suite = "MacAlertsTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite) ?? .standard, suite)
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func device(_ ip: String) -> DiscoveredDevice {
    DiscoveredDevice(
        ipAddress: ip, hostname: nil, vendor: nil, macAddress: nil,
        latency: nil, discoveredAt: Date(), source: .local
    )
}

private final class DeviceListBox: @unchecked Sendable {
    var devices: [DiscoveredDevice]
    init(_ devices: [DiscoveredDevice]) { self.devices = devices }
}

private struct ListUpsertPhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "alertsFixtureUpsert"
    let displayName = "Alerts fixture upsert"
    let weight: Double = 1.0
    let box: DeviceListBox

    func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
        for device in box.devices {
            await accumulator.upsert(device)
        }
        await onProgress(1.0)
    }
}

/// Answers each check from a script of reachable flags; once the script runs out it repeats the last one.
private actor ScriptedMonitorService: NetMonitor_macOS.NetworkMonitorService {
    private var script: [Bool]
    private(set) var checks = 0
    init(_ script: [Bool]) { self.script = script }

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        checks += 1
        let reachable = script.count > 1 ? script.removeFirst() : (script.first ?? true)
        return MeasurementResult(
            targetID: request.id, timestamp: Date(), latency: reachable ? 5 : nil,
            isReachable: reachable, errorMessage: reachable ? nil : "down (stub)"
        )
    }
}

// MARK: - MacAlertNotifier

@Suite("MacAlertNotifier")
@MainActor
struct MacAlertNotifierTests {
    @Test func freshInstallSendsBothAlerts() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let poster = FakeNotificationPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        alerts.targetWentDown(name: "Router", host: "192.0.2.1")
        alerts.devicesJoined([LocalDevice(ipAddress: "192.0.2.9", macAddress: "")])

        #expect(poster.categories == [NotificationService.targetDownCategory, NotificationService.newDeviceCategory])
    }

    @Test func eachToggleTurnsItsAlertOff() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let poster = FakeNotificationPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        defaults.set(false, forKey: NotificationService.targetDownAlertKey)
        alerts.targetWentDown(name: "Router", host: "192.0.2.1")
        #expect(poster.requests.isEmpty)

        defaults.set(false, forKey: NotificationService.newDeviceAlertKey)
        alerts.devicesJoined([LocalDevice(ipAddress: "192.0.2.9", macAddress: "")])
        #expect(poster.requests.isEmpty)
    }

    @Test func enableNotificationsOffSilencesEveryAlert() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: MacAlertNotifier.notificationsEnabledKey)
        let poster = FakeNotificationPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        alerts.targetWentDown(name: "Router", host: "192.0.2.1")
        alerts.devicesJoined([LocalDevice(ipAddress: "192.0.2.9", macAddress: "")])

        #expect(poster.requests.isEmpty)
    }
}

// MARK: - MonitoringSession target-down

@Suite("MonitoringSession target-down alert", .serialized)
@MainActor
struct MonitoringSessionTargetDownAlertTests {
    /// Runs monitoring until `checks` checks have happened and returns the names alerted.
    private func run(script: [Bool], checks: Int, retryCount: Int? = nil) async throws -> [String] {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let target = NetworkTarget(name: "Router", host: "192.0.2.1", targetProtocol: .icmp, checkInterval: 0.01, isEnabled: true)
        context.insert(target)
        try context.save()

        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        if let retryCount {
            defaults.set(true, forKey: CheckRetryPolicy.enabledKey)
            defaults.set(retryCount, forKey: CheckRetryPolicy.countKey)
        }

        let stub = ScriptedMonitorService(script)
        let session = MonitoringSession(
            modelContext: context,
            anyHTTPService: stub, anyICMPService: stub, anyTCPService: stub,
            defaults: defaults
        )
        var alerted: [String] = []
        session.onTargetDown = { name, _ in alerted.append(name) }
        session.startMonitoring()
        let deadline = ContinuousClock.now + .seconds(10)
        while await stub.checks < checks, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await session.stopMonitoringAndWait()
        return alerted
    }

    @Test func alertsOnceWhenATargetGoesDownAndStaysDown() async throws {
        let alerted = try await run(script: [true, false, false, false], checks: 4)
        #expect(alerted == ["Router"])
    }

    @Test func alertsAgainAfterTheTargetRecoversAndFailsAgain() async throws {
        let alerted = try await run(script: [false, true, false, true], checks: 4)
        #expect(alerted == ["Router", "Router"])
    }

    @Test func noAlertWhenRetriesRecoverBeforeTheThreshold() async throws {
        // Two failures then success, with a threshold of 3: never marked down.
        let alerted = try await run(script: [false, false, true], checks: 3, retryCount: 3)
        #expect(alerted.isEmpty)
    }
}

// MARK: - DeviceDiscoveryCoordinator new devices

@Suite("DeviceDiscoveryCoordinator new-device hook", .serialized)
@MainActor
struct DeviceDiscoveryNewDeviceHookTests {
    @Test func reportsOnlyDevicesAddedAfterTheFirstScan() async throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let box = DeviceListBox([device("192.0.2.1"), device("192.0.2.2")])
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in
                ScanPipeline(steps: [ScanPipeline.Step(phases: [ListUpsertPhase(box: box)], concurrent: false)])
            },
            portChecker: { _, _, _ in false }
        )
        var reported: [[String]] = []
        coordinator.onNewDevices = { devices in reported.append(devices.map(\.ipAddress).sorted()) }

        // First scan of the network records a baseline and alerts nothing.
        coordinator.startScan()
        await waitUntil { !coordinator.isScanning }
        #expect(reported.isEmpty)

        // A later scan that finds a never-seen device reports just that one.
        box.devices = [device("192.0.2.1"), device("192.0.2.2"), device("192.0.2.3")]
        coordinator.startScan()
        await waitUntil { !coordinator.isScanning }
        #expect(reported == [["192.0.2.3"]])

        // Seeing the same devices again reports nothing.
        coordinator.startScan()
        await waitUntil { !coordinator.isScanning }
        #expect(reported == [["192.0.2.3"]])
    }
}
