import Foundation
import SwiftData
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("CompanionMessageHandler Extended", .serialized)
@MainActor
struct CompanionMessageHandlerExtendedTests {

    // MARK: - Fixture

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

    // MARK: - statusUpdate Routing

    @Test func generateStatusUpdateReflectsMonitoringState() throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let message = handler.generateStatusUpdate()
        guard case .statusUpdate(let payload) = message else {
            #expect(Bool(false), "Expected .statusUpdate")
            return
        }
        // Default state: not monitoring, no targets
        #expect(payload.isMonitoring == false)
        #expect(payload.onlineTargets == 0)
        #expect(payload.offlineTargets == 0)
        #expect(payload.averageLatency == nil)
    }

    @Test func statusUpdateCommandRoutesToGenerateStatusUpdate() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .startMonitoring)), from: UUID())
        guard case .statusUpdate? = response else {
            #expect(Bool(false), "Expected .statusUpdate response from startMonitoring")
            return
        }
        #expect(true)
    }

    // MARK: - deviceListResponse Generation

    @Test func generateDeviceListWithNoDevicesIsEmpty() throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let message = handler.generateDeviceList()
        guard case .deviceList(let payload) = message else {
            #expect(Bool(false), "Expected .deviceList")
            return
        }
        #expect(payload.devices.isEmpty)
    }

    @Test func generateDeviceListMapsMultipleDevices() throws {
        let (container, _, handler, coordinator, _) = try makeFixture()
        _ = container

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:10", hostname: "printer"),
            LocalDiscoveredDevice(ipAddress: "192.168.1.11", macAddress: "AA:BB:CC:DD:EE:11", hostname: "camera"),
        ], profileID: nil)

        let message = handler.generateDeviceList()
        guard case .deviceList(let payload) = message else {
            #expect(Bool(false), "Expected .deviceList")
            return
        }
        #expect(payload.devices.count == 2)
        let ips = Set(payload.devices.map(\.ipAddress))
        #expect(ips.contains("192.168.1.10"))
        #expect(ips.contains("192.168.1.11"))
    }

    // MARK: - scanRequest Handling

    @Test func scanDevicesCommandReturnsToolResultSuccess() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .scanDevices)), from: UUID())
        guard case .toolResult(let payload)? = response else {
            #expect(Bool(false), "Expected .toolResult")
            return
        }
        #expect(payload.tool == "deviceScan")
        #expect(payload.success == true)
    }

    @Test func refreshDevicesCommandReturnsDeviceList() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .refreshDevices)), from: UUID())
        guard case .deviceList? = response else {
            #expect(Bool(false), "Expected .deviceList from refreshDevices")
            return
        }
        #expect(true)
    }

    // MARK: - Malformed / Error Messages

    @Test func malformedCommandWithUnknownActionReturnsError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .portScan)), from: UUID())
        guard case .error(let payload)? = response else {
            #expect(Bool(false), "Expected .error for unsupported portScan command")
            return
        }
        #expect(payload.code == "UNSUPPORTED_COMMAND")
        #expect(!payload.message.isEmpty)
    }

    @Test func dnsLookupCommandReturnsUnsupportedError() async throws {
        let (container, _, handler, _, _) = try makeFixture()
        _ = container

        let response = await handler.handle(.command(CommandPayload(action: .dnsLookup)), from: UUID())
        guard case .error(let payload)? = response else {
            #expect(Bool(false), "Expected .error for dnsLookup command")
            return
        }
        #expect(payload.code == "UNSUPPORTED_COMMAND")
        #expect(payload.message.contains("dnsLookup"))
    }
}
