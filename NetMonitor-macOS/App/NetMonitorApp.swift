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
            return try MacPersistence.makeOutcome(storeURL: nil, inMemory: inMemory)
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
                suggester: DeviceSuggester(service: InsightService.shared, store: DeviceSuggestionStore())
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

            companionService = CompanionService()
            let handler = companionHandler
            do {
                try await companionService?.start { @Sendable message, clientID in
                    return await handler?.handle(message, from: clientID)
                }
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
            suggester: Self.uiTestSuggester
        )
        discovery.changeTracker = UITestScanFixture.changeTracker(reset: HistoryFileLocation.current.resetRequested)
        deviceDiscovery = discovery
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--seed-test-device") {
            UITestScanFixture.seedDevice(
                into: context,
                profileID: profileManager.activeProfile?.id,
                deviceType: ProcessInfo.processInfo.environment["UITEST_FAKE_SUGGESTION"] == "1" ? .unknown : .computer
            )
            // UI tests don't scan, so ask about the seeded device directly (#449).
            discovery.startSuggestions(profileID: profileManager.activeProfile?.id)
        }
        // UI-test scans write events too; there is no alert dispatcher here (#491).
        let recorder = MacEventRecorder()
        recorder.attach(to: discovery)
        eventRecorder = recorder
        if arguments.contains("--seed-security-devices") {
            UITestScanFixture.seedSecurityDevices(into: context, profileID: profileManager.activeProfile?.id)
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
/// and a printer it has never seen. The seeded row is the network's baseline, so a scan reports
/// the printer, and only the printer, as first seen.
enum UITestScanFixture {
    /// The device tracker's own suite, so UI-test scans never touch the user's registry.
    static let trackerSuite = "netmonitor.uitest"
    static let seedIP = "192.168.77.77"
    static let seedMAC = "AA:BB:CC:DD:EE:FF"
    static let seedHostname = "uitest-device"
    static let printerIP = "192.168.77.20"
    static let printerMAC = "00:1B:A9:77:00:20"
    static let printerHostname = "uitest-printer"

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

    /// The UI-test tracker, emptied first when `reset` (`--reset-history-files`) is set.
    @MainActor
    static func changeTracker(reset: Bool) -> DeviceChangeTracker {
        // Never fall back to the standard defaults: that is the user's real registry.
        guard let defaults = UserDefaults(suiteName: trackerSuite) else {
            preconditionFailure("UI-test tracker suite \(trackerSuite) is unavailable")
        }
        if reset {
            defaults.removePersistentDomain(forName: trackerSuite)
        }
        return DeviceChangeTracker(defaults: defaults)
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
            for device in UITestScanFixture.devices {
                await accumulator.upsert(device)
            }
            await onProgress(1.0)
        }
    }
}
