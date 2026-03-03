//
//  CompanionMessageHandler.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import Foundation
import SwiftData
import NetMonitorCore
import Darwin

/// Handles incoming messages from companion apps
@MainActor
final class CompanionMessageHandler {

    private let modelContext: ModelContext
    private let monitoringSession: MonitoringSession
    private let deviceDiscovery: DeviceDiscoveryCoordinator
    private let wakeOnLanService: WakeOnLANService
    private let icmpService: ICMPMonitorService
    private let networkProfileManager: NetworkProfileManager

    init(
        modelContext: ModelContext,
        monitoringSession: MonitoringSession,
        deviceDiscovery: DeviceDiscoveryCoordinator,
        wakeOnLanService: WakeOnLANService,
        icmpService: ICMPMonitorService,
        networkProfileManager: NetworkProfileManager
    ) {
        self.modelContext = modelContext
        self.monitoringSession = monitoringSession
        self.deviceDiscovery = deviceDiscovery
        self.wakeOnLanService = wakeOnLanService
        self.icmpService = icmpService
        self.networkProfileManager = networkProfileManager
    }

    /// Process an incoming message and return an optional response
    func handle(_ message: CompanionMessage, from _: UUID) async -> CompanionMessage? {
        switch message {
        case .command(let payload):
            return await handleCommand(payload)

        case .heartbeat:
            return .heartbeat(HeartbeatPayload())

        case .networkProfile(let payload):
            return handleNetworkProfileSync(payload)

        default:
            return nil
        }
    }

    /// Generate current status update message
    func generateStatusUpdate() -> CompanionMessage {
        let results = monitoringSession.latestResults.values
        let online = results.filter { $0.isReachable }.count
        let offline = results.filter { !$0.isReachable }.count
        let latencies = results.compactMap { $0.latency }
        let avgLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        return .statusUpdate(StatusUpdatePayload(
            isMonitoring: monitoringSession.isMonitoring,
            onlineTargets: online,
            offlineTargets: offline,
            averageLatency: avgLatency
        ))
    }

    /// Generate target list message
    func generateTargetList() -> CompanionMessage {
        let descriptor = FetchDescriptor<NetworkTarget>()
        let targets = (try? modelContext.fetch(descriptor)) ?? []

        let targetInfos = targets.map { target in
            let measurement = monitoringSession.latestMeasurement(for: target.id)
            return TargetInfo(
                id: target.id,
                name: target.name,
                host: target.host,
                port: target.port,
                protocol: target.targetProtocol.rawValue,
                isEnabled: target.isEnabled,
                isReachable: measurement?.isReachable,
                latency: measurement?.latency
            )
        }

        return .targetList(TargetListPayload(targets: targetInfos))
    }

    /// Generate device list message
    func generateDeviceList() -> CompanionMessage {
        let deviceInfos = deviceDiscovery.discoveredDevices.map { device in
            DeviceInfo(
                id: device.id,
                ipAddress: device.ipAddress,
                macAddress: device.macAddress,
                hostname: device.hostname,
                vendor: device.vendor,
                deviceType: device.deviceType.rawValue,
                isOnline: device.status == .online
            )
        }

        return .deviceList(DeviceListPayload(devices: deviceInfos))
    }

    // MARK: - Private Methods

    private func handleCommand(_ payload: CommandPayload) async -> CompanionMessage? {
        switch payload.action {
        case .startMonitoring:
            monitoringSession.startMonitoring()
            return generateStatusUpdate()

        case .stopMonitoring:
            monitoringSession.stopMonitoring()
            return generateStatusUpdate()

        case .scanDevices:
            deviceDiscovery.startScan()
            return .toolResult(ToolResultPayload(
                tool: "deviceScan",
                success: true,
                result: "Scan started"
            ))

        case .refreshTargets:
            return generateTargetList()

        case .refreshDevices:
            return generateDeviceList()

        case .ping:
            return await handlePingCommand(payload.parameters)

        case .wakeOnLan:
            return await handleWakeOnLan(payload.parameters)

        default:
            return .error(ErrorPayload(
                code: "UNSUPPORTED_COMMAND",
                message: "Command '\(payload.action.rawValue)' is not yet implemented"
            ))
        }
    }

    private func handlePingCommand(_ parameters: [String: String]?) async -> CompanionMessage {
        guard let host = parameters?["host"] else {
            return .error(ErrorPayload(
                code: "MISSING_PARAMETER",
                message: "Ping requires 'host' parameter"
            ))
        }

        // Create Sendable DTO for ping check
        let request = TargetCheckRequest(
            id: UUID(),
            host: host,
            port: nil,
            targetProtocol: .icmp,
            timeout: 10
        )

        do {
            let result = try await icmpService.check(request: request)
            if result.isReachable, let latency = result.latency {
                return .toolResult(ToolResultPayload(
                    tool: "ping",
                    success: true,
                    result: "Reply from \(host): time=\(Int(latency))ms"
                ))
            } else {
                return .toolResult(ToolResultPayload(
                    tool: "ping",
                    success: false,
                    result: result.errorMessage ?? "No response from \(host)"
                ))
            }
        } catch {
            return .toolResult(ToolResultPayload(
                tool: "ping",
                success: false,
                result: "Ping failed: \(error.localizedDescription)"
            ))
        }
    }

    private func handleWakeOnLan(_ parameters: [String: String]?) async -> CompanionMessage {
        guard let mac = parameters?["mac"] else {
            return .error(ErrorPayload(
                code: "MISSING_PARAMETER",
                message: "Wake on LAN requires 'mac' parameter"
            ))
        }

        do {
            let _ = await wakeOnLanService.wake(macAddress: mac, broadcastAddress: "255.255.255.255", port: 9)
            return .toolResult(ToolResultPayload(
                tool: "wakeOnLan",
                success: true,
                result: "Magic packet sent to \(mac)"
            ))
        } catch {
            return .toolResult(ToolResultPayload(
                tool: "wakeOnLan",
                success: false,
                result: "Failed to wake \(mac): \(error.localizedDescription)"
            ))
        }
    }

    private func handleNetworkProfileSync(_ payload: NetworkProfilePayload) -> CompanionMessage? {
        let companionName = payload.sourceDeviceName.map { "\($0) Network" } ?? payload.name
        guard networkProfileManager.upsertCompanionProfile(
            gateway: payload.gatewayIP,
            subnet: payload.subnet,
            name: companionName,
            interfaceName: payload.interfaceName
        ) != nil else {
            return nil
        }

        NotificationCenter.default.post(name: .networkProfilesDidChange, object: nil)
        networkProfileManager.detectLocalNetwork()
        guard let localProfile = networkProfileManager.profiles.first(where: { $0.isLocal })
                ?? networkProfileManager.activeProfile else {
            return nil
        }

        let response = NetworkProfilePayload(
            name: localProfile.displayName,
            gatewayIP: localProfile.gatewayIP,
            subnet: localProfile.subnet,
            interfaceName: localProfile.interfaceName,
            sourceDeviceName: Host.current().localizedName
        )
        return .networkProfile(response)
    }
}
