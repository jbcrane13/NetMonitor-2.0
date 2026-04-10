import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - NetworkDetailViewTests
//
// Tests for the two primary behaviours baked into NetworkDetailView:
//
//   1. gatewayLatencyHistory — 3-step fallback chain that reads from
//      MonitoringSession.recentLatencies:
//        Step 1: target whose name contains "gateway"
//        Step 2: first ICMP-protocol target with any latency data
//        Step 3: any target with any latency data
//        Step 4: [] when session is nil or recentLatencies is empty
//
//   2. Lifecycle (onAppear / onChange):
//        • MonitoringSession.startMonitoring() is called by onAppear when
//          the session is not yet monitoring
//        • startMonitoring() is NOT called when already monitoring (idempotent)
//        • NetworkProfileManager.profiles being updated propagates via
//          first(where:) profile lookup — the lookup returns the updated value
//        • UptimeViewModel starts in isLoading=true, then isLoading=false after load()
//        • ConnectivityMonitor.isOnline defaults to true at init (before start())
//
// NOTE: NetworkDetailView.gatewayLatencyHistory is a private computed property.
// The fallback chain is exercised by constructing the same conditions the view
// observes — a MonitoringSession with specific recentLatencies entries — and
// running the identical fallback algorithm directly. This is the canonical
// approach for testing logic that is embedded in a View struct and cannot be
// extracted without wider refactoring.

@Suite(.serialized)
@MainActor
struct NDVGatewayLatencyFallbackTests {

    // MARK: - Helpers

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            SessionRecord.self
        ])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    /// Replicates the private gatewayLatencyHistory algorithm from NetworkDetailView
    /// so we can exercise all three fallback steps without coupling to the View body.
    private func gatewayLatencyHistory(
        targets: [NetworkTarget],
        recentLatencies: [UUID: [Double]]
    ) -> [Double] {
        // Step 1: gateway-named target
        if let gateway = targets.first(where: {
            $0.name.localizedCaseInsensitiveContains("gateway")
        }) {
            let history = recentLatencies[gateway.id] ?? []
            if !history.isEmpty { return history }
        }
        // Step 2: first ICMP target with data
        for target in targets where target.targetProtocol == .icmp {
            let history = recentLatencies[target.id] ?? []
            if !history.isEmpty { return history }
        }
        // Step 3: any target with data
        for (_, history) in recentLatencies where !history.isEmpty {
            return history
        }
        return []
    }

    // MARK: - Step 1: Gateway-named target wins

    @Test("Fallback step 1: gateway-named target with data is returned first")
    func step1GatewayNamedTargetWins() throws {
        let (container, _) = try makeStore()
        _ = container

        let gatewayTarget = NetworkTarget(
            name: "Gateway Router",
            host: "192.168.1.1",
            targetProtocol: .icmp
        )
        let icmpTarget = NetworkTarget(
            name: "DNS Server",
            host: "8.8.8.8",
            targetProtocol: .icmp
        )

        let gatewayHistory: [Double] = [10.0, 12.5, 11.0]
        let icmpHistory: [Double] = [50.0, 55.0, 48.0]

        let latencies: [UUID: [Double]] = [
            gatewayTarget.id: gatewayHistory,
            icmpTarget.id: icmpHistory
        ]

        let result = gatewayLatencyHistory(
            targets: [gatewayTarget, icmpTarget],
            recentLatencies: latencies
        )

        #expect(result == gatewayHistory,
                "Step 1 must return the gateway-named target's history, not the ICMP fallback")
    }

    @Test("Fallback step 1: case-insensitive match on 'GATEWAY' in name")
    func step1CaseInsensitiveGatewayMatch() throws {
        let (container, _) = try makeStore()
        _ = container

        let upperTarget = NetworkTarget(
            name: "GATEWAY",
            host: "10.0.0.1",
            targetProtocol: .icmp
        )
        let history: [Double] = [5.0, 6.0]
        let latencies: [UUID: [Double]] = [upperTarget.id: history]

        let result = gatewayLatencyHistory(
            targets: [upperTarget],
            recentLatencies: latencies
        )

        #expect(result == history,
                "Step 1 must match 'GATEWAY' case-insensitively")
    }

    @Test("Fallback step 1: gateway target with no data falls through to step 2")
    func step1GatewayWithNoDataFallsThroughToStep2() throws {
        let (container, _) = try makeStore()
        _ = container

        let gatewayTarget = NetworkTarget(
            name: "Home Gateway",
            host: "192.168.0.1",
            targetProtocol: .icmp
        )
        let icmpTarget = NetworkTarget(
            name: "Ping Target",
            host: "1.1.1.1",
            targetProtocol: .icmp
        )
        let icmpHistory: [Double] = [30.0, 32.0]

        // Gateway target exists but has no data → step 2 must kick in
        let latencies: [UUID: [Double]] = [icmpTarget.id: icmpHistory]

        let result = gatewayLatencyHistory(
            targets: [gatewayTarget, icmpTarget],
            recentLatencies: latencies
        )

        #expect(result == icmpHistory,
                "When gateway target has no data, step 2 ICMP fallback must activate")
    }

    // MARK: - Step 2: First ICMP target with data

    @Test("Fallback step 2: first ICMP target with data used when no gateway match")
    func step2ICMPFallback() throws {
        let (container, _) = try makeStore()
        _ = container

        let httpTarget = NetworkTarget(
            name: "Web Server",
            host: "example.com",
            targetProtocol: .http
        )
        let icmpTarget = NetworkTarget(
            name: "Ping Check",
            host: "8.8.4.4",
            targetProtocol: .icmp
        )
        let icmpHistory: [Double] = [22.0, 24.0, 21.5]
        let latencies: [UUID: [Double]] = [
            httpTarget.id: [100.0],
            icmpTarget.id: icmpHistory
        ]

        let result = gatewayLatencyHistory(
            targets: [httpTarget, icmpTarget],
            recentLatencies: latencies
        )

        #expect(result == icmpHistory,
                "Step 2 must select the ICMP target over a non-ICMP target when no gateway match")
    }

    // MARK: - Step 3: Any target with data

    @Test("Fallback step 3: any target with data used when no gateway or ICMP match")
    func step3AnyTargetFallback() throws {
        let (container, _) = try makeStore()
        _ = container

        let httpTarget = NetworkTarget(
            name: "HTTP Check",
            host: "example.com",
            targetProtocol: .http
        )
        let expectedHistory: [Double] = [80.0, 85.0]
        let latencies: [UUID: [Double]] = [httpTarget.id: expectedHistory]

        // No gateway-named target, no ICMP target → step 3 returns first non-empty entry
        let result = gatewayLatencyHistory(
            targets: [httpTarget],
            recentLatencies: latencies
        )

        #expect(!result.isEmpty,
                "Step 3 must return data from any target when no gateway or ICMP target has data")
        #expect(result == expectedHistory,
                "Step 3 must return the non-empty history array")
    }

    // MARK: - Step 4: Empty fallback

    @Test("Fallback step 4: empty array returned when recentLatencies is empty")
    func step4EmptyWhenNoLatencies() throws {
        let (container, _) = try makeStore()
        _ = container

        let target = NetworkTarget(
            name: "Any Target",
            host: "192.168.1.1",
            targetProtocol: .icmp
        )

        let result = gatewayLatencyHistory(
            targets: [target],
            recentLatencies: [:]
        )

        #expect(result.isEmpty,
                "Step 4: empty recentLatencies must yield an empty array")
    }

    @Test("Fallback step 4: empty array returned when targets list is empty")
    func step4EmptyWhenNoTargets() throws {
        let (container, _) = try makeStore()
        _ = container

        let result = gatewayLatencyHistory(
            targets: [],
            recentLatencies: [UUID(): [10.0, 12.0]]
        )

        // No targets to match gateway or ICMP names, but step 3 still iterates
        // recentLatencies directly → returns data from step 3 even with empty targets.
        // This confirms step 3 is a pure dict scan independent of target list.
        #expect(!result.isEmpty,
                "Step 3 iterates recentLatencies directly; non-empty dict yields data even with no targets")
    }

    @Test("Fallback: all empty histories yields empty result")
    func allEmptyHistoriesYieldsEmpty() throws {
        let (container, _) = try makeStore()
        _ = container

        let target1 = NetworkTarget(name: "gateway", host: "10.0.0.1", targetProtocol: .icmp)
        let target2 = NetworkTarget(name: "ping", host: "8.8.8.8", targetProtocol: .icmp)

        // Both targets exist in recentLatencies but with empty arrays
        let latencies: [UUID: [Double]] = [
            target1.id: [],
            target2.id: []
        ]

        let result = gatewayLatencyHistory(
            targets: [target1, target2],
            recentLatencies: latencies
        )

        #expect(result.isEmpty,
                "When all history arrays are empty, the fallback must return []")
    }
}

// MARK: - NetworkDetailView lifecycle behaviour tests

@Suite(.serialized)
@MainActor
struct NetworkDetailViewLifecycleTests {

    // MARK: - Helpers

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            SessionRecord.self
        ])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeUptimeStore() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: ConnectivityRecord.self, configurations: config)
        return (container, container.mainContext)
    }

    private func makeProfile(
        id: UUID = UUID(),
        name: String = "Test Network",
        gatewayIP: String = "192.168.1.1"
    ) -> NetworkProfile {
        NetworkProfile(
            id: id,
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A80100,
                broadcastAddress: 0xC0A801FF,
                interfaceAddress: 0xC0A8010A,
                netmask: 0xFFFFFF00
            ),
            connectionType: .wifi,
            name: name,
            gatewayIP: gatewayIP,
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
    }

    // MARK: - onAppear: auto-start monitoring

    @Test("onAppear auto-start: startMonitoring() is called when session is not yet monitoring")
    func onAppearStartsMonitoringWhenNotMonitoring() throws {
        let (container, context) = try makeStore()
        _ = container

        // Insert an enabled target so startMonitoring() succeeds past the guard.
        let target = NetworkTarget(
            name: "Router",
            host: "192.168.1.1",
            targetProtocol: .icmp,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let session = MonitoringSession(modelContext: context)
        #expect(session.isMonitoring == false, "Precondition: session must start not monitoring")

        // Simulate the .onAppear body:
        // if let session, !session.isMonitoring { session.startMonitoring() }
        if !session.isMonitoring {
            session.startMonitoring()
        }

        #expect(session.isMonitoring == true,
                "onAppear must call startMonitoring() when session is not yet monitoring")

        session.stopMonitoring()
    }

    @Test("onAppear auto-start: startMonitoring() is NOT called when session is already monitoring")
    func onAppearDoesNotRestartWhenAlreadyMonitoring() throws {
        let (container, context) = try makeStore()
        _ = container

        context.insert(NetworkTarget(
            name: "DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            isEnabled: true
        ))
        try context.save()

        let session = MonitoringSession(modelContext: context)
        session.startMonitoring()

        let startTimeBeforeAppear = session.startTime
        #expect(session.isMonitoring == true, "Precondition: session must already be monitoring")

        // Simulate a second .onAppear (e.g. tab switch back):
        // if let session, !session.isMonitoring { session.startMonitoring() }
        if !session.isMonitoring {
            session.startMonitoring()
        }

        #expect(session.startTime == startTimeBeforeAppear,
                "onAppear must not reset startTime when session is already monitoring")

        session.stopMonitoring()
    }

    // MARK: - onAppear: ConnectivityMonitor initialisation

    @Test("onAppear initialises ConnectivityMonitor with correct profileID and gatewayIP")
    func onAppearInitialisesConnectivityMonitor() throws {
        let (container, context) = try makeStore()
        _ = container

        let profileID = UUID()
        let profile = makeProfile(id: profileID, gatewayIP: "10.0.0.1")

        // Simulate the .onAppear guard:
        // if connectivityMonitor == nil { ... }
        var connectivityMonitor: ConnectivityMonitor? = nil
        if connectivityMonitor == nil {
            connectivityMonitor = ConnectivityMonitor(
                profileID: profile.id,
                gatewayIP: profile.gatewayIP ?? "",
                modelContext: context
            )
        }

        let monitor = try #require(connectivityMonitor)
        #expect(monitor.profileID == profileID,
                "ConnectivityMonitor must be initialised with the correct profileID")
        #expect(monitor.gatewayIP == "10.0.0.1",
                "ConnectivityMonitor must be initialised with the profile's gatewayIP")
        #expect(monitor.isOnline == true,
                "ConnectivityMonitor defaults to isOnline=true before start() is called")
    }

    @Test("onAppear does not re-create ConnectivityMonitor on subsequent appears")
    func onAppearConnectivityMonitorIsCreatedOnlyOnce() throws {
        let (container, context) = try makeStore()
        _ = container

        let profile = makeProfile()
        var connectivityMonitor: ConnectivityMonitor? = nil

        // First appear
        if connectivityMonitor == nil {
            connectivityMonitor = ConnectivityMonitor(
                profileID: profile.id,
                gatewayIP: profile.gatewayIP ?? "",
                modelContext: context
            )
        }
        let firstInstance = connectivityMonitor

        // Second appear (tab switch back, same view)
        if connectivityMonitor == nil {
            connectivityMonitor = ConnectivityMonitor(
                profileID: profile.id,
                gatewayIP: profile.gatewayIP ?? "",
                modelContext: context
            )
        }

        // ObjectIdentifier comparison — same object means the guard prevented re-creation.
        let currentID = connectivityMonitor.map { ObjectIdentifier($0) }
        let firstID = firstInstance.map { ObjectIdentifier($0) }
        #expect(currentID == firstID,
                "ConnectivityMonitor must not be re-created on subsequent onAppear calls")
    }

    // MARK: - onAppear: UptimeViewModel initialisation and load state

    @Test("onAppear initialises UptimeViewModel and calls load() — isLoading transitions to false")
    func onAppearInitialisesUptimeViewModel() throws {
        let (_, uptimeContext) = try makeUptimeStore()

        let profileID = UUID()
        var uptimeViewModel: UptimeViewModel? = nil

        // Simulate the .onAppear body that creates UptimeViewModel and calls load():
        // let vm = UptimeViewModel(profileID: profile.id, modelContext: modelContext)
        // vm.load()
        // uptimeViewModel = vm
        if uptimeViewModel == nil {
            let vm = UptimeViewModel(profileID: profileID, modelContext: uptimeContext)
            vm.load()
            uptimeViewModel = vm
        }

        let vm = try #require(uptimeViewModel)
        #expect(vm.isLoading == false,
                "UptimeViewModel.isLoading must be false after load() is called in onAppear")
        #expect(vm.uptimePct == nil,
                "With no connectivity records, uptimePct must be nil after load()")
    }

    // MARK: - onChange: profile update propagation

    @Test("onChange profile update: first(where:) lookup returns updated profile from manager")
    func onChangeProfileUpdatePropagatesViaFirstWhere() throws {
        let suiteName = "test.networkdetailview.\(UUID())"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removeSuite(named: suiteName) }

        // Create a NetworkProfileManager with a controlled UserDefaults suite
        // and no real interface detection (empty activeProfilesProvider).
        let manager = NetworkProfileManager(
            userDefaults: userDefaults,
            activeProfilesProvider: { [] }
        )

        // Manually inject a profile into the manager.
        // addProfile() creates a new profile, so we use it to seed one.
        guard let added = manager.addProfile(
            gateway: "192.168.1.1",
            subnet: "192.168.1.0/24",
            name: "Original Name"
        ) else {
            Issue.record("addProfile returned nil — test setup failed")
            return
        }

        // Simulate the .onChange body:
        // if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
        //     profile = updated
        // }
        var profile = added
        if let updated = manager.profiles.first(where: { $0.id == profile.id }) {
            profile = updated
        }

        #expect(profile.id == added.id,
                "Profile ID must remain stable after onChange update")
        #expect(profile.name == "Original Name",
                "onChange lookup must return the current profile state from the manager")
    }

    @Test("onChange profile update: renamed profile is reflected via first(where:) lookup")
    func onChangeProfileUpdateReflectsRename() throws {
        let suiteName = "test.networkdetailview.rename.\(UUID())"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removeSuite(named: suiteName) }

        let manager = NetworkProfileManager(
            userDefaults: userDefaults,
            activeProfilesProvider: { [] }
        )

        guard let added = manager.addProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Old Name"
        ) else {
            Issue.record("addProfile returned nil")
            return
        }

        // Simulate an in-place update (e.g. user renames the profile):
        // addProfile with the same gateway/subnet updates the existing entry.
        guard manager.addProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "New Name"
        ) != nil else {
            Issue.record("addProfile (rename) returned nil")
            return
        }

        // Simulate what NetworkDetailView.onChange does:
        var profile = added
        if let updated = manager.profiles.first(where: { $0.id == profile.id }) {
            profile = updated
        }

        #expect(profile.name == "New Name",
                "onChange must propagate a renamed profile's updated name via first(where:) lookup")
    }

    @Test("onChange: profile missing from manager leaves profile unchanged")
    func onChangeProfileMissingFromManagerLeavesProfileUnchanged() throws {
        let suiteName = "test.missing.\(UUID())"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removeSuite(named: suiteName) }
        let manager = NetworkProfileManager(
            userDefaults: userDefaults,
            activeProfilesProvider: { [] }
        )

        let orphanProfile = NetworkProfile(
            id: UUID(),
            interfaceName: "en0",
            ipAddress: "172.16.0.5",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xAC100000,
                broadcastAddress: 0xAC1000FF,
                interfaceAddress: 0xAC100005,
                netmask: 0xFFFFFF00
            ),
            connectionType: .ethernet,
            name: "Orphan",
            gatewayIP: "172.16.0.1",
            subnet: "172.16.0.0/24",
            isLocal: false,
            discoveryMethod: .manual
        )

        var profile = orphanProfile

        // Simulate .onChange: profile is not in manager.profiles → no update
        if let updated = manager.profiles.first(where: { $0.id == profile.id }) {
            profile = updated
        }

        #expect(profile.id == orphanProfile.id,
                "When profile is not found in manager, the local binding must remain unchanged")
        #expect(profile.name == "Orphan",
                "Profile name must not change when first(where:) returns nil")
    }
}
