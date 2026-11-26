// swiftlint:disable function_body_length
import SwiftUI
import UserNotifications
import SwiftData
import NetMonitorCore
import NetworkScanKit
import os

@main
struct NetMonitorApp: App {
    @State private var monitoringSession: MonitoringSession?
    @State private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @State private var companionService: CompanionService?
    @State private var networkChangeWatcher: LocalNetworkChangeMonitor?
    @State private var periodicScanScheduler: PeriodicScanScheduler?
    /// One store for every window and the rule dispatcher (#394).
    @State private var alertRuleStore = AlertRuleStore(defaults: UITestPlainRules.ruleDefaults())
    @State private var speedTestScheduler: ScheduledSpeedTestRunner?
    @State private var speedTestMaintenance: SpeedTestHistoryMaintenance?
    @State private var companionHandler: CompanionMessageHandler?
    @State private var menuBarController: MenuBarController?
    @State private var notificationService: NotificationService?
    @State private var notificationPresenter: MacNotificationPresenter?
    @State private var alertDispatcher: MacAlertDispatcher?
    @State private var networkProfileManager: NetworkProfileManager?
    /// Writes the Mac's network events (#491).
    @State private var eventRecorder: MacEventRecorder?
    /// Records connectivity for the local network whichever screen is showing (#491 D8).
    @State private var connectivityMonitor: AppConnectivityMonitor?
    @State private var healthSampler: MacHealthSampler?

    @AppStorage("autoStartMonitoring") private var autoStartMonitoring = false
    @AppStorage("netmonitor.appearance.accentColor") private var accentColorHex = "#06B6D4"
    @AppStorage("netmonitor.appearance.compactMode") private var compactMode = false
    @AppStorage("netmonitor.appearance.theme") private var appearanceRaw = AppearanceMode.system.rawValue

    init() {
        // Save events still waiting for the write debounce (#491).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            NetworkEventService.shared.flush()
        }
    }

    private var colorSchemeOverride: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceRaw) ?? .system {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    private var shouldDisableMonitoring: Bool {
        isUITesting || ProcessInfo.processInfo.environment["DISABLE_MONITORING"] == "1"
    }

    private var isUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting") ||
           arguments.contains("--disable-local-auth") {
            return true
        }
        let env = ProcessInfo.processInfo.environment
        if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
           env["XCUITest"] == "1" ||
           env["UITEST_MODE"] == "1" ||
           env["CI"] == "true" {
            return true
        }
        if NSClassFromString("XCTest") != nil {
            return true
        }
        return false
    }

    private static let persistenceOutcome: PersistenceBootstrapOutcome<ModelContainer> = {
        do {
            // `--in-memory-store` keeps an evidence run off the user's saved data; UI tests always
            // are, since their scans save fixture devices (#491).
            let arguments = ProcessInfo.processInfo.arguments
            let inMemory = NSClassFromString("XCTest") != nil
                || arguments.contains("--in-memory-store") || arguments.contains("--uitesting")
            let outcome = try MacPersistence.makeOutcome(storeURL: nil, inMemory: inMemory)
            // Device groups made consistent, and serial notes lines moved into the field (#561, #594).
            DeviceStoreMaintenance.runAtLaunch(on: outcome.store)
            return outcome
        } catch {
            fatalError("Could not create recovery ModelContainer: \(error)")
        }
    }()

    private static var sharedModelContainer: ModelContainer { persistenceOutcome.store }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if let recovery = Self.persistenceOutcome.recovery {
                    PersistenceRecoveryView(recovery: recovery)
                } else if let monitoringSession, let deviceDiscovery {
                    ContentView()
                        .presenceEnvironment()
                        .environment(monitoringSession)
                        .environment(deviceDiscovery)
                        .environment(networkProfileManager)
                        .environment(alertRuleStore)
                } else {
                    ProgressView("Starting NetMonitor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                // Skip full setup when running unit tests — test host
                // doesn't need real services, and seeding NetworkTargets
                // into the shared container causes SwiftData crashes
                // when test containers reset.
                guard NSClassFromString("XCTest") == nil,
                      !Self.persistenceOutcome.isDegraded else { return }
                await setupServices()
            }
            // Apply appearance based on user preference (.system = follow macOS,
            // .dark = force dark, .light = force light).
            // MacTheme now uses adaptive colors (Color(NSColor { traits in ... }))
            // that look correct in both modes.
            .preferredColorScheme(colorSchemeOverride)
            .tint(Color(hex: accentColorHex))
            .environment(\.appAccentColor, Color(hex: accentColorHex))
            .environment(\.compactMode, compactMode)
            .environment(\.companionService, companionService)
            .captureOpenWindow()
        }
        .modelContainer(Self.sharedModelContainer)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            MenuBarCommands(
                isMonitoring: Binding(
                    get: { monitoringSession?.isMonitoring ?? false },
                    set: { _ in }
                ),
                startMonitoring: { monitoringSession?.startMonitoring() },
                stopMonitoring: { monitoringSession?.stopMonitoring() },
                scanNetwork: { deviceDiscovery?.rescan(.user(nil)) }
            )
        }

        Settings {
            SettingsView()
                .environment(networkProfileManager)
                .environment(deviceDiscovery)
                .environment(alertRuleStore)
                // The Rules tab starts monitoring a target it adds (#450).
                .environment(monitoringSession)
                .tint(Color(hex: accentColorHex))
                .environment(\.appAccentColor, Color(hex: accentColorHex))
                .environment(\.compactMode, compactMode)
                .environment(\.companionService, companionService)
                // Apply appearance for Settings window too
                .preferredColorScheme(colorSchemeOverride)
        }
        .modelContainer(Self.sharedModelContainer)
    }

    @MainActor
    private func setupServices() async {
        // Initialize Sentry error tracking
        if !isUITesting,
           let sentryDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"],
           !sentryDSN.isEmpty {
            ObservabilityService.shared.configure(
                dsn: sentryDSN,
                environment: "production"
            )
        }

        let context = Self.sharedModelContainer.mainContext

        if isUITesting {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            UserDefaults.standard.set(false, forKey: "autoStartMonitoring")
            setupUITestServices(context: context)
            return
        }

        await DefaultTargetsProvider.seedIfNeeded(modelContext: context)

        let httpService = HTTPMonitorService()
        let icmpService = ICMPMonitorService()
        let tcpService = TCPMonitorService()
        let bonjourScanner = BonjourDiscoveryService()
        let wakeOnLanService = WakeOnLANService()
        let profileManager = NetworkProfileManager()
        networkProfileManager = profileManager

        if monitoringSession == nil {
            monitoringSession = MonitoringSession(
                modelContext: context,
                httpService: httpService,
                icmpService: icmpService,
                tcpService: tcpService
            )
        }

        // Apply the history retention setting at launch, not only an hour into monitoring (#395).
        monitoringSession?.pruneOldMeasurements()

        if deviceDiscovery == nil {
            let discovery = DeviceDiscoveryCoordinator(
                modelContext: context,
                bonjourScanner: bonjourScanner,
                networkProfileManager: profileManager,
                reviewPrompt: RateAppService.reviewPrompt,
                // The on-device model suggests what unidentified devices are (#449).
                suggester: DeviceSuggester(service: InsightService.shared, store: DeviceSuggestionStore()),
                dispatcher: DeviceEventDispatcher.shared
            )
            deviceDiscovery = discovery
            // Network events and app-scope connectivity, before the first scan (#491).
            let recorder = MacEventRecorder()
            recorder.attach(to: discovery)
            recorder.localNetworkObserved(profileManager.localProfile)
            eventRecorder = recorder
            let connectivity = AppConnectivityMonitor(
                modelContext: context,
                // A reconnection counts for this network only if it is still the local one.
                isCurrent: { [weak profileManager] id in
                    profileManager?.detectLocalNetwork()
                    return profileManager?.localProfile?.id == id
                },
                onTransition: { [weak recorder] isOnline, profileID, timestamp in
                    recorder?.connectivityChanged(isOnline: isOnline, profileID: profileID, at: timestamp)
                }
            )
            connectivity.run(for: profileManager.localProfile)
            connectivityMonitor = connectivity
            // Fill the dashboard without waiting for the user to press Scan (#358).
            discovery.rescan(.launch)
            // Rescan when the Mac moves to a different network while the app is open (#359).
            let watcher = LocalNetworkChangeMonitor.rescanning(discovery, profileManager: profileManager) { [weak recorder] local in
                recorder?.localNetworkObserved(local)
                connectivity.run(for: local)
            }
            watcher.start()
            networkChangeWatcher = watcher
            // Rescan at the user's chosen scan frequency while the app runs (#392).
            let scheduler = PeriodicScanScheduler.rescanning(discovery)
            scheduler.start()
            periodicScanScheduler = scheduler
        }

        startSpeedTestSchedulerIfNeeded()
        startHealthSamplerIfNeeded(profileManager: profileManager)

        if let session = monitoringSession,
           let discovery = deviceDiscovery,
           companionService == nil {
            companionHandler = CompanionMessageHandler(
                modelContext: context,
                monitoringSession: session,
                deviceDiscovery: discovery,
                wakeOnLanService: wakeOnLanService,
                icmpService: icmpService,
                networkProfileManager: profileManager
            )

            companionService = CompanionService(credentials: makeCompanionCredentials())
            let handler = companionHandler
            do {
                // While a scan runs the Mac stops offering insight; tell connected phones (#457).
                let service = companionService
                handler?.onScanningChange { heartbeat in
                    Task { await service?.broadcast(.heartbeat(heartbeat)) }
                }
                // Each completed scan's inventory goes to the paired phones (#585).
                handler?.onScanCompleted { list in
                    Task { await service?.broadcast(list) }
                }
                try await companionService?.start(
                    heartbeat: { await handler?.heartbeat() ?? HeartbeatPayload() },
                    messageHandler: { @Sendable message, clientID, authorization in
                        await handler?.handle(message, from: clientID, authorization: authorization)
                    }
                )
            } catch {
                Logger.app.error("Failed to start companion service: \(error)")
            }
        }

        if let session = monitoringSession,
           let discovery = deviceDiscovery,
           menuBarController == nil {
            menuBarController = MenuBarController(monitoringSession: session, deviceDiscovery: discovery)
            menuBarController?.setup()
            // Target alerts' View Details opens the popover, which lists the targets (#478).
            NotificationRouter.shared.showTargets = { [weak menuBarController] in menuBarController?.showPopover() }
        }

        if notificationService == nil {
            let service = NotificationService()
            notificationService = service
            // Show alerts while the app is frontmost too; the center holds its delegate weakly (#403).
            let presenter = MacNotificationPresenter()
            UNUserNotificationCenter.current().delegate = presenter
            notificationPresenter = presenter
            if !isUITesting {
                Task {
                    _ = await notificationService?.requestAuthorization()
                }
            }
            // Target-down, recovery, latency, new-device and rule alerts (#403, #394, #486).
            let dispatcher = MacAlertDispatcher(service: service, store: alertRuleStore, insightService: InsightService.shared)
            alertDispatcher = dispatcher
            dispatcher.attach(to: monitoringSession, discovery: deviceDiscovery)
            // Target-device links whose target, device or rule is gone (#450).
            alertRuleStore.pruneLinks(in: Self.sharedModelContainer.mainContext)
        }

        if autoStartMonitoring && !shouldDisableMonitoring,
           let session = monitoringSession, !session.isMonitoring {
            session.startMonitoring()
        }
    }

    /// Services for UI tests: no monitoring, alerts or LAN scans (#449, #491).
    @MainActor
    private func setupUITestServices(context: ModelContext) {
        let httpService = HTTPMonitorService()
        let icmpService = ICMPMonitorService()
        let tcpService = TCPMonitorService()
        let profileManager = NetworkProfileManager(userDefaults: NetworkProfileDefaults.launchDefaults)
        networkProfileManager = profileManager
        monitoringSession = MonitoringSession(
            modelContext: context,
            httpService: httpService,
            icmpService: icmpService,
            tcpService: tcpService
        )
        // Scans see fixed devices, never the LAN, and remember them apart from the user's (#491).
        let discovery = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: profileManager,
            pipelineFactory: UITestScanFixture.pipelineFactory,
            suggester: Self.uiTestSuggester,
            scanHistory: UITestScanFixture.scanHistory(),
            clock: UITestScanFixture.scanClock ?? Date.init,
            presenceClock: UITestScanFixture.presenceClock ?? Date.init,
            dispatcher: DeviceEventDispatcher.shared
        )
        deviceDiscovery = discovery
        // Settings > Companion over in-memory credentials; the listener stays off, so a UI-test
        // launch never opens the companion port (#590).
        if companionService == nil {
            companionService = CompanionService(credentials: makeCompanionCredentials())
        }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--seed-test-device") {
            UITestScanFixture.seedDevice(
                into: context,
                profileID: profileManager.activeProfile?.id,
                deviceType: ProcessInfo.processInfo.environment["UITEST_FAKE_SUGGESTION"] == "1" ? .unknown : .computer
            )
            UITestScanFixture.recordBaseline(in: discovery, profileID: profileManager.activeProfile?.id)
            // UI tests don't scan, so ask about the seeded device directly (#449).
            discovery.startSuggestions(profileID: profileManager.activeProfile?.id)
        }
        // UI-test scans write events too; there is no alert dispatcher here (#491).
        let recorder = MacEventRecorder()
        recorder.attach(to: discovery)
        eventRecorder = recorder
        if arguments.contains("--seed-past-device") {
            UITestScanFixture.seedPastDevice(into: context, profileID: profileManager.activeProfile?.id)
        }
        if arguments.contains("--seed-security-devices") {
            UITestScanFixture.seedSecurityDevices(into: context, profileID: profileManager.activeProfile?.id)
        }
        if arguments.contains("--seed-device-group") {
            UITestScanFixture.seedDeviceGroup(into: context, profileID: profileManager.activeProfile?.id)
        }
        if arguments.contains("--seed-group-suggestion") {
            UITestScanFixture.seedGroupSuggestion(into: context, profileID: profileManager.activeProfile?.id)
        }
        if arguments.contains("--seed-test-events") {
            UITestScanFixture.seedEvents(into: NetworkEventService.shared, profileID: profileManager.activeProfile?.id)
        }
        UITestHealthHistory.seedIfRequested(networkProfileID: profileManager.localProfile?.id)
        ChangeBriefMacViewModel.configureForUITests(arguments: arguments)
        SecurityReadoutMacViewModel.configureForUITests(arguments: arguments)
        // Ask your network (#452): the printer and two joins this week.
        #if DEBUG
        if AskMacViewModel.uiTestMode(arguments: arguments) != nil {
            AskUITestFixture.seed(into: context, events: NetworkEventService.shared)
        }
        #endif
    }

    /// A health sample for the Mac's network every 15 minutes (#491 D10).
    private func startHealthSamplerIfNeeded(profileManager: NetworkProfileManager) {
        guard healthSampler == nil else { return }
        let sampler = MacHealthSampler(profileManager: profileManager)
        sampler.start()
        healthSampler = sampler
    }

    /// Optional scheduled speed tests while the app runs, off by default (#398).
    private func startSpeedTestSchedulerIfNeeded() {
        if speedTestMaintenance == nil {
            let maintenance = SpeedTestHistoryMaintenance()
            maintenance.start()
            speedTestMaintenance = maintenance
        }
        guard speedTestScheduler == nil, !isUITesting else { return }
        let runner = MacSpeedTestHistory.makeScheduler()
        runner.start()
        speedTestScheduler = runner
    }

    /// With `UITEST_FAKE_SUGGESTION=1`, UI tests get a fixed suggestion instead of the
    /// on-device model, remembered in a suite cleared at launch (#449). Otherwise none.
    private static var uiTestSuggester: DeviceSuggester? {
        guard ProcessInfo.processInfo.environment["UITEST_FAKE_SUGGESTION"] == "1",
              let defaults = UserDefaults(suiteName: "netmonitor.uitest.suggestions")
        else { return nil }
        defaults.removePersistentDomain(forName: "netmonitor.uitest.suggestions")
        return DeviceSuggester(service: FixedSuggestionInsightService(), store: DeviceSuggestionStore(defaults: defaults))
    }
}

// swiftlint:enable function_body_length

// MARK: - Companion credentials

@MainActor
extension NetMonitorApp {
    /// The companion link's identity and paired phones (#590). A `--uitesting` launch keeps them in
    /// memory, seeded by `--seed-paired-phones`; otherwise they live in this Mac's Keychain. When the
    /// Keychain refuses, the service stays off rather than running unauthenticated.
    func makeCompanionCredentials() -> CompanionCredentials? {
        #if DEBUG
        if isUITesting {
            let seeds = ProcessInfo.processInfo.arguments.contains("--seed-paired-phones") ? UITestCompanion.seedPhones : []
            // The launch's UI-test suite, emptied at launch (`NetworkProfileDefaults.launchDefaults`).
            _ = NetworkProfileDefaults.launchDefaults
            return .inMemory(seedPhones: seeds, defaultsSuite: NetworkProfileDefaults.uiTestSuite)
        }
        #endif
        do {
            return try .live()
        } catch {
            Logger.companion.error("Companion credentials unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

#if DEBUG
/// Paired phones for `--seed-paired-phones` (#590); made-up names and keys. Debug builds only.
enum UITestCompanion {
    static let seedPhones = [
        PairedPhone(pin: Data(repeating: 0xA1, count: 32), name: "Test iPhone", pairedAt: Date(timeIntervalSince1970: 1_798_000_000)),
        PairedPhone(pin: Data(repeating: 0xB2, count: 32), name: "Test iPad", pairedAt: Date(timeIntervalSince1970: 1_799_000_000))
    ]
}
#endif

// MARK: - Network profile defaults

/// Where the network list is saved (#346). A `--uitesting` launch gets its own suite, emptied at
/// every launch, so networks a UI test adds never reach the user's list or the next launch.
enum NetworkProfileDefaults {
    static let uiTestSuite = "netmonitor.uitest.networkProfiles"

    /// This launch's defaults, made once per process. Setup reruns when the main window is
    /// recreated, and that must not empty the suite again mid-launch.
    @MainActor static let launchDefaults = make(arguments: ProcessInfo.processInfo.arguments)

    static func make(arguments: [String], uiTestSuite: String = Self.uiTestSuite) -> UserDefaults {
        guard arguments.contains("--uitesting") else { return .standard }
        // Never fall back to the standard defaults: that is the user's real network list.
        guard let defaults = UserDefaults(suiteName: uiTestSuite) else {
            preconditionFailure("UI-test network profile suite \(uiTestSuite) is unavailable")
        }
        defaults.removePersistentDomain(forName: uiTestSuite)
        return defaults
    }
}

// MARK: - UI-test scan fixture

/// What `--uitesting` scans instead of the LAN (#491 D7): the `--seed-test-device` row's device
/// and a printer it has never seen. A scan of the seeded row alone is recorded at launch as the
/// network's baseline (its first recorded scan, on which nothing "joins", #603), so the first
/// fixture scan reports the printer, and only the printer, as joined.
enum UITestScanFixture {
    /// The UI-test scans' own suite (their scan history), so they never touch the user's.
    static let scanHistorySuite = "netmonitor.uitest"
    static let seedIP = "192.168.77.77"
    static let seedMAC = "AA:BB:CC:DD:EE:FF"
    static let seedHostname = "uitest-device"
    static let printerIP = "192.168.77.20"
    static let printerMAC = "00:1B:A9:77:00:20"
    static let printerHostname = "uitest-printer"

    /// Scans the fixture has answered, for `UITEST_SCAN_DROP_LAST`.
    @MainActor private static var scansRun = 0

    /// The fixture's scan: both devices, except that with `UITEST_SCAN_DROP_LAST=1` scans after
    /// the first no longer find the printer, so a UI test sees it go offline under grace (#596).
    @MainActor
    static func nextScan() -> [DiscoveredDevice] {
        defer { scansRun += 1 }
        let drops = ProcessInfo.processInfo.environment["UITEST_SCAN_DROP_LAST"] == "1" && scansRun > 0
        let scan = drops ? devices.filter { $0.ipAddress != printerIP } : devices
        // With the seeded group, only its second interface answers (#594).
        let group = ProcessInfo.processInfo.arguments.contains("--seed-device-group") ? [groupMemberScan] : []
        // UITEST_SCAN_BONJOUR_PAIR=1: two addresses answer for one strong Bonjour host (#594 PR2).
        let pair = ProcessInfo.processInfo.environment["UITEST_SCAN_BONJOUR_PAIR"] == "1" ? bonjourPairScan : []
        return scan + group + pair
    }

    static let workstationHost = "uitest-workstation.local"

    /// The workstation's Ethernet (192.168.77.70) and Wi-Fi (192.168.77.71) interfaces, both
    /// answering for `workstationHost`: the scan groups them automatically.
    private static var bonjourPairScan: [DiscoveredDevice] {
        [("192.168.77.70", "uitest-workstation"), ("192.168.77.71", "uitest-workstation-wifi")].map { ip, name in
            DiscoveredDevice(
                ipAddress: ip, hostname: name, vendor: nil, macAddress: "02:00:00:77:00:\(ip.suffix(2))", latency: 3,
                discoveredAt: Date(), source: .local,
                bonjourClaims: [HostClaim(host: workstationHost, service: "_ssh._tcp", address: ip)]
            )
        }
    }

    static let groupPrimaryIP = "192.168.77.60"
    static let groupMemberIP = "192.168.77.61"
    static let groupName = "UITest Studio Mac"

    private static var groupMemberScan: DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: groupMemberIP, hostname: "uitest-studio", vendor: nil, macAddress: "02:00:00:77:00:61",
            latency: 3, discoveredAt: Date(), source: .local
        )
    }

    /// With `UITEST_SCAN_CLOCK=1`: the time each scan happens, starting at launch and stepping
    /// 10 minutes per scan, so the grace interval passes without waiting (#596).
    @MainActor
    static var scanClock: (@MainActor () -> Date)? {
        guard ProcessInfo.processInfo.environment["UITEST_SCAN_CLOCK"] == "1" else { return nil }
        let start = Date()
        var ticks = 0
        return {
            defer { ticks += 1 }
            return start.addingTimeInterval(Double(ticks) * 600)
        }
    }

    /// With `UITEST_PRESENCE_OFFSET=<seconds>` (#583): presence is shown as of that long after the
    /// wall clock, so a network scanned at launch reads "Not checked recently".
    @MainActor
    static var presenceClock: (@MainActor () -> Date)? {
        guard let offset = ProcessInfo.processInfo.environment["UITEST_PRESENCE_OFFSET"].flatMap(TimeInterval.init) else { return nil }
        return { Date().addingTimeInterval(offset) }
    }

    /// The reconciler's scan history in the tracker's suite, emptied at every launch: a stepped
    /// `scanClock` leaves scans dated ahead, which would make the next launch's scans look older
    /// and be skipped.
    @MainActor
    static func scanHistory() -> ScanHistory {
        guard let defaults = UserDefaults(suiteName: scanHistorySuite) else {
            preconditionFailure("UI-test scan-history suite \(scanHistorySuite) is unavailable")
        }
        let history = ScanHistory(defaults: defaults)
        history.clearAll()
        return history
    }

    static var devices: [DiscoveredDevice] {
        [
            DiscoveredDevice(
                ipAddress: seedIP, hostname: seedHostname, vendor: nil, macAddress: seedMAC,
                latency: 5, discoveredAt: Date(), source: .local
            ),
            DiscoveredDevice(
                ipAddress: printerIP, hostname: printerHostname, vendor: nil, macAddress: printerMAC,
                latency: 4, discoveredAt: Date(), source: .local
            )
        ]
    }

    static let pipelineFactory: @Sendable (ScanPipelineInputs) -> ScanPipeline = { _ in
        ScanPipeline(steps: [ScanPipeline.Step(phases: [FixturePhase()], concurrent: false)])
    }

    /// Reconciles a scan of the seeded device alone, a minute before launch: the network's first
    /// recorded scan, so later fixture scans can report devices joining (#603).
    @MainActor
    static func recordBaseline(in discovery: DeviceDiscoveryCoordinator, profileID: UUID?) {
        let seed = DiscoveredDevice(
            ipAddress: seedIP, hostname: seedHostname, vendor: nil, macAddress: seedMAC, latency: 5, discoveredAt: Date(), source: .local
        )
        discovery.reconcileScan([seed], profileID: profileID, now: Date().addingTimeInterval(-60))
    }

    /// Seeds the baseline `LocalDevice` on `profileID`, for UI tests that need a non-empty
    /// devices list. Idempotent: does nothing when any device exists.
    @MainActor
    static func seedDevice(into context: ModelContext, profileID: UUID?, deviceType: DeviceType = .computer) {
        if let existing = try? context.fetch(FetchDescriptor<LocalDevice>()), !existing.isEmpty {
            return
        }
        context.insert(LocalDevice(
            ipAddress: seedIP,
            macAddress: seedMAC,
            hostname: seedHostname,
            deviceType: deviceType,
            status: .online,
            lastLatency: 5.0,
            networkProfileID: profileID
        ))
        try? context.save()
    }

    /// `--seed-past-device` (#583): an offline TV last seen 8 days ago, a past device the list
    /// hides behind "Show past devices". Added beside any other seeded device.
    @MainActor
    static func seedPastDevice(into context: ModelContext, profileID: UUID?) {
        let row = LocalDevice(
            ipAddress: "192.168.77.50", macAddress: "02:00:00:77:00:50", hostname: "uitest-old-tv",
            deviceType: .tv, status: .offline, networkProfileID: profileID
        )
        row.lastSeen = Date().addingTimeInterval(-8 * 86400)
        context.insert(row)
        try? context.save()
    }

    /// `--seed-security-devices` (#454): a camera with telnet and HTTP open and a NAS with SMB open,
    /// for the security readout. Added beside any other seeded device.
    @MainActor
    static func seedSecurityDevices(into context: ModelContext, profileID: UUID?) {
        context.insert(LocalDevice(
            ipAddress: "192.168.77.30", macAddress: "02:00:00:77:00:30", hostname: "uitest-camera",
            deviceType: .camera, status: .online, openPorts: [23, 80], networkProfileID: profileID
        ))
        context.insert(LocalDevice(
            ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:40", hostname: "uitest-nas",
            deviceType: .storage, status: .online, openPorts: [445], networkProfileID: profileID
        ))
        try? context.save()
    }

    /// `--seed-device-group` (#594): one device on two interfaces, written through
    /// `DeviceGroupWriter`: the primary (Ethernet, offline since two hours ago) holds the name and
    /// notes, and the Wi-Fi interface has notes of its own. The fixture scan finds only the Wi-Fi
    /// interface, so the device reads Online through its second member.
    @MainActor
    static func seedDeviceGroup(into context: ModelContext, profileID: UUID?) {
        let primary = LocalDevice(
            ipAddress: groupPrimaryIP, macAddress: "02:00:00:77:00:60", hostname: "uitest-studio",
            deviceType: .computer, status: .offline, networkProfileID: profileID
        )
        primary.customName = groupName
        primary.notes = "Ethernet port behind the desk"
        primary.serialNumber = "C02UITEST0001"
        primary.serialSource = IdentitySource.userConfirmed.rawValue
        primary.lastSeen = Date().addingTimeInterval(-2 * 3600)
        primary.firstSeen = primary.lastSeen.addingTimeInterval(-86400)
        let member = LocalDevice(
            ipAddress: groupMemberIP, macAddress: "02:00:00:77:00:61", hostname: "uitest-studio",
            deviceType: .computer, status: .offline, networkProfileID: profileID
        )
        member.notes = "Wi-Fi when undocked"
        member.lastSeen = primary.lastSeen
        var rows = [primary, member]
        // UITEST_GROUP_THIRD=1: a third interface, so the group outlives removing the primary.
        if ProcessInfo.processInfo.environment["UITEST_GROUP_THIRD"] == "1" {
            let third = LocalDevice(
                ipAddress: "192.168.77.62", macAddress: "02:00:00:77:00:62", hostname: "uitest-studio",
                deviceType: .computer, status: .offline, networkProfileID: profileID
            )
            third.lastSeen = primary.lastSeen
            rows.append(third)
        }
        rows.forEach(context.insert)
        try? context.save()
        try? DeviceGroupWriter(context: context).group(rows.map(\.id), primary: primary.id, source: .user)
    }

    /// `--seed-group-suggestion` (#594 PR2): a laptop saved as two devices (192.168.77.80 and .81)
    /// whose addresses answered for the same strong Bonjour host an hour ago, so device detail
    /// suggests they are the same device. Neither answers the fixture scan.
    @MainActor
    static func seedGroupSuggestion(into context: ModelContext, profileID: UUID?) {
        // Seen together, so once grouped the device shows at the lower address.
        let seen = Date()
        for (ip, name) in [("192.168.77.80", "uitest-laptop"), ("192.168.77.81", "uitest-laptop-wifi")] {
            let row = LocalDevice(
                ipAddress: ip, macAddress: "02:00:00:77:00:\(ip.suffix(2))", hostname: name, deviceType: .laptop, status: .online,
                networkProfileID: profileID
            )
            row.lastSeen = seen
            row.firstSeen = seen
            row.bonjourHost = "uitest-laptop.local"
            row.bonjourHostSeenAt = Date().addingTimeInterval(-3600)
            context.insert(row)
        }
        try? context.save()
    }

    /// `--seed-test-events`: one event today and one ten days ago, for the Timeline's ranges.
    static func seedEvents(into eventService: any NetworkEventServiceProtocol, profileID: UUID?, now: Date = Date()) {
        eventService.log(NetworkEvent(
            type: .connectivityChange, timestamp: now.addingTimeInterval(-10 * 86400),
            title: "UITest Event 10 Days Ago", networkProfileID: profileID
        ))
        // A minute ago, but never before today's midnight, so it is always "Today" (as on iOS).
        eventService.log(NetworkEvent(
            type: .connectivityChange, timestamp: max(now.addingTimeInterval(-60), Calendar.current.startOfDay(for: now)),
            title: "UITest Event Today", networkProfileID: profileID
        ))
    }

    private struct FixturePhase: ScanPhase, Sendable {
        let id: ScanPhaseID = "uiTestFixture"
        let displayName = "UI-test fixture"
        let weight: Double = 1.0

        func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
            for device in await UITestScanFixture.nextScan() {
                await accumulator.upsert(device)
            }
            await onProgress(1.0)
        }
    }
}
