import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("CompanionMessageHandler", .serialized)
@MainActor
struct CompanionMessageHandlerTests {

    @Test func handleHeartbeatReturnsHeartbeatMessage() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.heartbeat(HeartbeatPayload()), from: UUID())
        if case .heartbeat? = response {
            #expect(true)
        } else {
            #expect(Bool(false))
        }
    }

    @Test func unsupportedCommandReturnsStructuredError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .traceroute)), from: UUID())
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "UNSUPPORTED_COMMAND")
        #expect(payload.message.contains("traceroute"))
    }

    @Test func pingCommandWithoutHostReturnsMissingParameterError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(
            .command(CommandPayload(action: .ping, parameters: [:])),
            from: UUID()
        )
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "MISSING_PARAMETER")
        #expect(payload.message.contains("host"))
    }

    @Test func wakeOnLanCommandWithoutMacReturnsMissingParameterError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(
            .command(CommandPayload(action: .wakeOnLan, parameters: [:])),
            from: UUID()
        )
        guard case .error(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.code == "MISSING_PARAMETER")
        #expect(payload.message.contains("mac"))
    }

    @Test func refreshTargetsCommandReturnsPersistedTargets() async throws {
        let (container, context, handler, _, _) = try makeFixture()
        _ = container

        context.insert(NetworkTarget(
            name: "Gateway",
            host: "192.168.1.1",
            targetProtocol: .icmp
        ))
        context.insert(NetworkTarget(
            name: "Cloudflare",
            host: "1.1.1.1",
            targetProtocol: .icmp
        ))
        try context.save()

        let response = await handler.handle(.command(CommandPayload(action: .refreshTargets)), from: UUID())
        guard case .targetList(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.targets.count == 2)
        #expect(Set(payload.targets.map(\.name)) == Set(["Gateway", "Cloudflare"]))
    }

    @Test func startMonitoringWithNoEnabledTargetsReturnsStatusUpdateNotMonitoring() async throws {
        let (container, context, handler, _, _) = try makeFixture()
        _ = container

        context.insert(NetworkTarget(
            name: "Disabled",
            host: "8.8.8.8",
            targetProtocol: .icmp,
            isEnabled: false
        ))
        try context.save()

        let response = await handler.handle(.command(CommandPayload(action: .startMonitoring)), from: UUID())
        guard case .statusUpdate(let payload)? = response else {
            #expect(Bool(false))
            return
        }

        #expect(payload.isMonitoring == false)
        #expect(payload.onlineTargets == 0)
        #expect(payload.offlineTargets == 0)
    }

    @Test func generateDeviceListMapsCoordinatorDevicesToCompanionPayload() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(
                ipAddress: "192.168.1.44",
                macAddress: "AA:BB:CC:DD:EE:44",
                hostname: "office-printer.local"
            )
        ], profileID: nil)

        let message = handler.generateDeviceList()
        guard case .deviceList(let payload) = message else {
            #expect(Bool(false))
            return
        }

        #expect(payload.devices.count == 1)
        #expect(payload.devices[0].ipAddress == "192.168.1.44")
        #expect(payload.devices[0].hostname == "office-printer.local")
        #expect(payload.devices[0].isOnline == true)
    }

    private func makeFixture() throws -> (
        ModelContainer,
        ModelContext,
        CompanionMessageHandler,
        DeviceDiscoveryCoordinator,
        MonitoringSession
    ) {
        let schema = Schema([
            NetworkTarget.self,
            TargetMeasurement.self,
            SessionRecord.self,
            LocalDevice.self
        ])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let networkProfileManager = NetworkProfileManager()
        let monitoringSession = MonitoringSession(modelContext: context)
        let deviceDiscovery = DeviceDiscoveryCoordinator(
            modelContext: context,
            arpScanner: ARPScannerService(timeout: 0.05),
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: networkProfileManager
        )

        let handler = CompanionMessageHandler(
            modelContext: context,
            monitoringSession: monitoringSession,
            deviceDiscovery: deviceDiscovery,
            wakeOnLanService: WakeOnLANService(),
            icmpService: ICMPMonitorService(),
            networkProfileManager: networkProfileManager
        )

        return (container, context, handler, deviceDiscovery, monitoringSession)
    }
}
