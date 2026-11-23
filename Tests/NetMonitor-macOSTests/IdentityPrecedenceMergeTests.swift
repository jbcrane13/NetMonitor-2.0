import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// ADR-022 (#462): a saved device's maker, model and friendly name change only to an equal or
/// higher-ranked value, across scans.
@Suite(.serialized)
@MainActor
struct IdentityPrecedenceMergeTests {

    private func makeCoordinator() throws -> (ModelContainer, ModelContext, DeviceDiscoveryCoordinator) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        return (container, container.mainContext, coordinator)
    }

    private func scan(_ identity: DeviceIdentity) -> LocalDiscoveredDevice {
        LocalDiscoveredDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan", identity: identity)
    }

    private func row(in context: ModelContext) throws -> LocalDevice {
        try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
    }

    /// #443: Bonjour is time-boxed, so a later scan may hear only UPnP.
    @Test("A Bonjour model stays when a later scan has only a UPnP model or a guess")
    func bonjourModelStaysAcrossScans() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("AppleTV14,1", source: .bonjour)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("Apple TV 4K", source: .upnp)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("Apple TV", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.model == IdentityValue("AppleTV14,1", source: .bonjour))

        // A newer Bonjour model replaces it: equal rank, newer wins.
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("AppleTV14,2", source: .bonjour)))], profileID: nil)
        #expect(try row(in: context).modelName == "AppleTV14,2")
    }

    @Test("A guess fills an empty maker, and the device's own maker replaces it")
    func guessThenAnnouncement() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).maker == "Meross")
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross Technology", source: .upnp)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(maker: IdentityValue("Meross", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.maker == IdentityValue("Meross Technology", source: .upnp))
    }

    @Test("A value saved before sources were stored gives way to any sourced value")
    func unsourcedValueGivesWay() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        let saved = LocalDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan")
        saved.modelName = "Q80"
        context.insert(saved)
        try context.save()
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("TV", source: .hostnameGuess)))], profileID: nil)
        #expect(try row(in: context).identity.model == IdentityValue("TV", source: .hostnameGuess))
    }

    @Test("A UniFi name outranks a UPnP name; neither is written into the hostname")
    func friendlyNames() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(friendlyName: IdentityValue("Blake's TV", source: .unifi)))], profileID: nil)
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(friendlyName: IdentityValue("[TV] Samsung Q80", source: .upnp)))], profileID: nil)
        let device = try row(in: context)
        #expect(device.friendlyName == "Blake's TV")
        #expect(device.hostname == "living-room.lan")
        #expect(device.displayName == "Blake's TV")
    }

    /// A device known only by its UPnP name kept that name in `hostname` before SchemaV3; now
    /// it's a friendly name. Private-MAC rotation still has a name to compare.
    @Test("A UPnP-named device with a private MAC keeps its row when the MAC rotates")
    func upnpNamedPrivateMACRotates() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        let saved = LocalDevice(ipAddress: "192.168.2.60", macAddress: "AA:BB:CC:00:00:01", hostname: "Living Room TV")
        context.insert(saved) // as 2.2.x saved it: the friendly name in hostname
        try context.save()

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.2.60", macAddress: "AA:BB:CC:00:00:02", hostname: nil,
                identity: DeviceIdentity(friendlyName: IdentityValue("Living Room TV", source: .upnp))
            )
        ], profileID: nil)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1)
        #expect(rows.first?.macAddress == "AA:BB:CC:00:00:02")
    }

    @Test("Device name: custom name, else friendly name, else hostname, else IP")
    func deviceNameOrder() {
        let device = LocalDevice(ipAddress: "192.168.2.50", macAddress: "")
        #expect(device.displayName == "192.168.2.50")
        device.hostname = "living-room.lan"
        #expect(device.displayName == "living-room.lan")
        device.resolvedHostname = "tv.lan"
        #expect(device.displayName == "tv.lan")
        device.friendlyName = "Living Room TV"
        #expect(device.displayName == "Living Room TV")
        device.customName = "Big TV"
        #expect(device.displayName == "Big TV")
    }

    /// #439: rows saved before hostname identity, for devices that no longer answer scans.
    @Test("A saved row the scan didn't find gets a guessed maker from its name; a saved maker stays")
    func staleRowIsFilledFromItsName() throws {
        let (container, context, coordinator) = try makeCoordinator()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.168.2.108", macAddress: "", hostname: "wiz_fcd4aa.lan", status: .offline))
        context.insert(LocalDevice(ipAddress: "192.168.2.2", macAddress: "", hostname: "unifi-pro-max-16-switch.lan", status: .offline))
        // An unranked maker from an older build, and a MAC-prefix maker: neither is replaced.
        let legacy = LocalDevice(ipAddress: "192.168.2.154", macAddress: "", hostname: "samsung-microwave.lan", status: .offline)
        legacy.manufacturer = "SmartThings"
        context.insert(legacy)
        context.insert(LocalDevice(
            ipAddress: "192.168.2.30", macAddress: "", hostname: "unifi-pro-max-16-switch", vendor: "Raspberry Pi Trading", status: .offline
        ))
        try context.save()

        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)

        let byIP = try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<LocalDevice>()).map { ($0.ipAddress, $0) })
        #expect(byIP["192.168.2.108"]?.identity.maker == IdentityValue("WiZ", source: .hostnameGuess))
        #expect(byIP["192.168.2.108"]?.vendor == nil)
        #expect(byIP["192.168.2.2"]?.maker == "Ubiquiti")
        #expect(byIP["192.168.2.2"]?.identity.model == IdentityValue("UniFi Pro Max 16 Switch", source: .hostnameGuess))
        #expect(byIP["192.168.2.154"]?.identity.maker == IdentityValue("SmartThings", source: nil))
        #expect(byIP["192.168.2.30"]?.maker == "Raspberry Pi Trading")
        #expect(byIP["192.168.2.30"]?.modelName == nil)
    }
}

/// #449: a model suggestion is the lowest-ranked identity source, so every scanned or saved
/// value beats it, and the coordinator runs one suggestion pass after each completed scan.
@Suite(.serialized)
@MainActor
struct ModelSuggestionMacTests {

    /// UserDefaults for one test, removed when the test ends.
    private final class TestDefaults {
        let name = "ModelSuggestionMacTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            // swiftlint:disable:next force_unwrapping
            defaults = UserDefaults(suiteName: name)!
        }

        deinit {
            defaults.removePersistentDomain(forName: name)
        }
    }

    nonisolated private static let scannedSources: [IdentitySource] = [.hostnameGuess, .upnp, .bonjour]
    private static let suggestion = DeviceSuggestion(maker: "Acme", model: "Box 1", confidence: .high)

    private let testDefaults = TestDefaults()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSuggester(_ service: any InsightServiceProtocol) -> DeviceSuggester {
        DeviceSuggester(service: service, store: DeviceSuggestionStore(defaults: testDefaults.defaults))
    }

    private func scan(_ identity: DeviceIdentity) -> LocalDiscoveredDevice {
        LocalDiscoveredDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan", identity: identity)
    }

    private func row(in context: ModelContext) throws -> LocalDevice {
        try #require(try context.fetch(FetchDescriptor<LocalDevice>()).first)
    }

    // MARK: - Precedence

    @Test("A suggestion survives a scan with no identity, and a scanned value replaces it", arguments: scannedSources)
    func scannedValueReplacesSuggestion(source: IdentitySource) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context, bonjourScanner: BonjourDiscoveryService(), networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        let suggester = makeSuggester(MockInsightService(suggestion: Self.suggestion))

        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)
        try await suggester.suggest(for: [row(in: context)])
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)
        #expect(try row(in: context).identity.maker == IdentityValue("Acme", source: .modelSuggestion))
        #expect(try row(in: context).identity.model == IdentityValue("Box 1", source: .modelSuggestion))

        let scanned = DeviceIdentity(maker: IdentityValue("Globex", source: source), model: IdentityValue("Box 2", source: source))
        coordinator.mergeDiscoveredDevices([scan(scanned)], profileID: nil)
        // The evidence changed, so the model is asked again; its answer still loses.
        try await suggester.suggest(for: [row(in: context)])
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)

        let device = try row(in: context)
        #expect(device.identity.maker == IdentityValue("Globex", source: source))
        #expect(device.identity.model == IdentityValue("Box 2", source: source))
        #expect(!suggester.isShowingSuggestion(device))
    }

    @Test("A suggestion never replaces a value a scan already saved", arguments: scannedSources)
    func suggestionNeverReplacesScannedValue(source: IdentitySource) async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context, bonjourScanner: BonjourDiscoveryService(), networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        let service = MockInsightService(suggestion: Self.suggestion)
        let suggester = makeSuggester(service)

        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity(model: IdentityValue("Box 2", source: source)))], profileID: nil)
        try await suggester.suggest(for: [row(in: context)])
        coordinator.mergeDiscoveredDevices([scan(DeviceIdentity())], profileID: nil)

        let device = try row(in: context)
        #expect(service.suggestionRequests.count == 1)
        #expect(device.identity.model == IdentityValue("Box 2", source: source))
        // The empty maker is still filled by the suggestion.
        #expect(device.identity.maker == IdentityValue("Acme", source: .modelSuggestion))
    }

    @Test("A suggestion never replaces a value saved before sources were stored")
    func suggestionNeverReplacesSourcelessValue() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let saved = LocalDevice(ipAddress: "192.168.2.50", macAddress: "", hostname: "living-room.lan", manufacturer: "SmartThings")
        saved.modelName = "Q80"
        context.insert(saved)
        try context.save()

        await makeSuggester(MockInsightService(suggestion: Self.suggestion)).suggest(for: [saved])

        #expect(saved.identity.maker == IdentityValue("SmartThings", source: nil))
        #expect(saved.identity.model == IdentityValue("Q80", source: nil))
    }

    // MARK: - Coordinator

    private func makeScanningCoordinator(
        suggester: DeviceSuggester
    ) throws -> (ModelContainer, DeviceDiscoveryCoordinator, UUID) {
        let container = try makeContainer()
        let local = NetworkProfile(
            id: UUID(),
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A80100,
                broadcastAddress: 0xC0A801FF,
                interfaceAddress: 0xC0A80101,
                netmask: 0xFFFFFF00
            ),
            connectionType: .wifi,
            name: "Home",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: testDefaults.defaults, activeProfilesProvider: { [local] }),
            // Empty pipeline: scans complete at once and keep the saved rows (#309).
            pipelineFactory: { _ in ScanPipeline(steps: []) },
            suggester: suggester
        )
        return (container, coordinator, local.id)
    }

    /// Runs a scan to completion, then waits for its suggestion pass.
    private func scanAndSuggest(_ coordinator: DeviceDiscoveryCoordinator) async {
        coordinator.startScan()
        let deadline = ContinuousClock.now + .seconds(10)
        while coordinator.isScanning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        await coordinator.suggestionTask?.value
    }

    @Test("A completed scan asks about each eligible device once; unchanged evidence isn't asked again")
    func scanCompletionSuggestsOncePerDevice() async throws {
        let service = MockInsightService(suggestion: Self.suggestion)
        let (container, coordinator, profileID) = try makeScanningCoordinator(suggester: makeSuggester(service))
        let context = container.mainContext
        let named = LocalDevice(ipAddress: "192.168.1.17", macAddress: "", hostname: "box-17.lan", networkProfileID: profileID)
        let withServices = LocalDevice(
            ipAddress: "192.168.1.18", macAddress: "", discoveredServices: ["_ipp._tcp"], networkProfileID: profileID
        )
        let nothingToGoOn = LocalDevice(ipAddress: "192.168.1.19", macAddress: "", networkProfileID: profileID)
        let otherNetwork = LocalDevice(ipAddress: "192.168.1.20", macAddress: "", hostname: "elsewhere.lan", networkProfileID: UUID())
        [named, withServices, nothingToGoOn, otherNetwork].forEach(context.insert)
        try context.save()

        await scanAndSuggest(coordinator)

        #expect(service.suggestionRequests.count == 2)
        #expect(named.identity.model == IdentityValue("Box 1", source: .modelSuggestion))
        #expect(coordinator.isShowingSuggestion(named))
        #expect(otherNetwork.modelName == nil)
        #expect(!context.hasChanges)

        await scanAndSuggest(coordinator)

        #expect(service.suggestionRequests.count == 2)
    }

    @Test("Stopping the scan stops the suggestion pass before it writes")
    func stopScanCancelsSuggestions() async throws {
        let service = SuspendingInsightService(suggestion: Self.suggestion)
        let suggester = makeSuggester(service)
        let (container, coordinator, profileID) = try makeScanningCoordinator(suggester: suggester)
        let device = LocalDevice(ipAddress: "192.168.1.17", macAddress: "", hostname: "box-17.lan", networkProfileID: profileID)
        container.mainContext.insert(device)
        try container.mainContext.save()

        coordinator.startScan()
        let deadline = ContinuousClock.now + .seconds(10)
        while service.calls == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(service.calls == 1)
        coordinator.stopScan()
        await coordinator.suggestionTask?.value

        #expect(device.modelName == nil)
        #expect(!suggester.isShowingSuggestion(device))
    }

    @Test("Accept writes the suggested type and confirms the model; dismiss hides a suggested type")
    func acceptAndDismiss() async throws {
        let service = MockInsightService(suggestion: DeviceSuggestion(deviceType: .printer, model: "Box 1", confidence: .medium))
        let (container, coordinator, profileID) = try makeScanningCoordinator(suggester: makeSuggester(service))
        let context = container.mainContext
        let accepted = LocalDevice(ipAddress: "192.168.1.17", macAddress: "", hostname: "box-17.lan", networkProfileID: profileID)
        let dismissed = LocalDevice(ipAddress: "192.168.1.18", macAddress: "", hostname: "box-18.lan", networkProfileID: profileID)
        context.insert(accepted)
        context.insert(dismissed)
        try context.save()

        await scanAndSuggest(coordinator)
        #expect(coordinator.suggestedType(for: accepted) == .printer)
        #expect(accepted.deviceType == .unknown)

        let revision = coordinator.suggestionRevision
        coordinator.acceptSuggestion(for: accepted)
        #expect(accepted.deviceType == .printer)
        #expect(accepted.identity.model == IdentityValue("Box 1", source: .userConfirmed))
        #expect(!coordinator.isShowingSuggestion(accepted))
        #expect(!context.hasChanges)
        #expect(coordinator.suggestionRevision > revision)

        coordinator.dismissSuggestion(for: dismissed)
        #expect(coordinator.suggestedType(for: dismissed) == nil)
        #expect(dismissed.modelName == nil)
        #expect(!coordinator.isShowingSuggestion(dismissed))
        #expect(!context.hasChanges)
    }

    @Test("Without a suggester a scan asks nothing and shows no suggestion")
    func noSuggesterByDefault() async throws {
        let container = try makeContainer()
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: container.mainContext, bonjourScanner: BonjourDiscoveryService(), networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        let device = LocalDevice(ipAddress: "192.168.1.17", macAddress: "", hostname: "box-17.lan")
        container.mainContext.insert(device)

        await scanAndSuggest(coordinator)

        #expect(coordinator.suggestionTask == nil)
        #expect(!coordinator.isShowingSuggestion(device))
    }
}

/// Answers a suggestion only after a long wait, so a test can cancel the pass mid-call.
private final class SuspendingInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let suggestion: DeviceSuggestion

    init(suggestion: DeviceSuggestion) {
        self.suggestion = suggestion
    }

    var isAvailable: Bool { true }
    var calls: Int { lock.withLock { count } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { $0.finish() }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        lock.withLock { count += 1 }
        try? await Task.sleep(for: .seconds(30))
        return suggestion
    }
}
