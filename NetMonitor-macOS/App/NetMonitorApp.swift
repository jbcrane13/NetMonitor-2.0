import SwiftUI
import SwiftData
import NetMonitorCore
import os

@main
struct NetMonitorApp: App {
    @State private var monitoringSession: MonitoringSession?
    @State private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @State private var companionService: CompanionService?
    @State private var companionHandler: CompanionMessageHandler?
    @State private var menuBarController: MenuBarController?
    @State private var notificationService: NotificationService?
    @State private var networkProfileManager: NetworkProfileManager?

    @AppStorage("autoStartMonitoring") private var autoStartMonitoring = false
    @AppStorage("netmonitor.appearance.accentColor") private var accentColorHex = "#06B6D4"
    @AppStorage("netmonitor.appearance.compactMode") private var compactMode = false

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
        if NSClassFromString("XCTest") != nil { return true }
        return false
    }

    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            // Keep container init on a single schema path to avoid the
            // launch-time "Duplicate version checksums detected" exception.
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            Logger.app.warning("Could not create persistent ModelContainer: \(error)")
            do {
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [inMemoryConfig])
            } catch {
                fatalError("Could not create in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if let monitoringSession, let deviceDiscovery {
                    ContentView()
                        .environment(monitoringSession)
                        .environment(deviceDiscovery)
                        .environment(networkProfileManager)
                } else {
                    ProgressView("Starting NetMonitor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                await setupServices()
            }
            .tint(Color(hex: accentColorHex))
            .environment(\.appAccentColor, Color(hex: accentColorHex))
            .environment(\.compactMode, compactMode)
            .captureOpenWindow()
        }
        .modelContainer(Self.sharedModelContainer)
        .commands {
            MenuBarCommands(
                isMonitoring: Binding(
                    get: { monitoringSession?.isMonitoring ?? false },
                    set: { _ in }
                ),
                startMonitoring: { monitoringSession?.startMonitoring() },
                stopMonitoring: { monitoringSession?.stopMonitoring() }
            )
        }

        Settings {
            SettingsView()
                .tint(Color(hex: accentColorHex))
                .environment(\.appAccentColor, Color(hex: accentColorHex))
                .environment(\.compactMode, compactMode)
        }
        .modelContainer(Self.sharedModelContainer)
    }

    @MainActor
    private func setupServices() async {
        let context = Self.sharedModelContainer.mainContext

        if isUITesting {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            UserDefaults.standard.set(false, forKey: "autoStartMonitoring")
        }

        if isUITesting {
            let httpService = HTTPMonitorService()
            let icmpService = ICMPMonitorService()
            let tcpService = TCPMonitorService()
            let profileManager = NetworkProfileManager()
            networkProfileManager = profileManager
            monitoringSession = MonitoringSession(
                modelContext: context,
                httpService: httpService,
                icmpService: icmpService,
                tcpService: tcpService
            )
            deviceDiscovery = DeviceDiscoveryCoordinator(
                modelContext: context,
                arpScanner: ARPScannerService(),
                bonjourScanner: BonjourDiscoveryService(),
                networkProfileManager: profileManager
            )
            return
        }

        await DefaultTargetsProvider.seedIfNeeded(modelContext: context)

        let httpService = HTTPMonitorService()
        let icmpService = ICMPMonitorService()
        let tcpService = TCPMonitorService()
        let arpScanner = ARPScannerService()
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

        if deviceDiscovery == nil {
            deviceDiscovery = DeviceDiscoveryCoordinator(
                modelContext: context,
                arpScanner: arpScanner,
                bonjourScanner: bonjourScanner,
                networkProfileManager: profileManager
            )
        }

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

        if let session = monitoringSession, menuBarController == nil {
            menuBarController = MenuBarController(monitoringSession: session)
            menuBarController?.setup()
        }

        if notificationService == nil {
            notificationService = NotificationService()
            if !isUITesting {
                Task {
                    _ = await notificationService?.requestAuthorization()
                }
            }
        }

        if autoStartMonitoring && !shouldDisableMonitoring,
           let session = monitoringSession, !session.isMonitoring {
            session.startMonitoring()
        }
    }
}
