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
    /// Answers the iPhone's insight requests with this Mac's model (#457).
    private let insightResponder: CompanionInsightResponder

    /// Settings key for "Answer model requests from iPhone"; off when unset.
    nonisolated static let answersInsightKey = "netmonitor.companion.answersInsight"

    /// Whether the user lets this Mac answer the iPhone's model requests. Off until the owner turns
    /// it on (#457). Only a paired iPhone reaches this handler (#590); whether to turn it on by
    /// default is a separate decision.
    nonisolated static var answersInsight: Bool {
        UserDefaults.standard.object(forKey: answersInsightKey) as? Bool ?? false
    }

    init(
        modelContext: ModelContext,
        monitoringSession: MonitoringSession,
        deviceDiscovery: DeviceDiscoveryCoordinator,
        wakeOnLanService: WakeOnLANService,
        icmpService: ICMPMonitorService,
        networkProfileManager: NetworkProfileManager,
        insightService: any InsightServiceProtocol = InsightService.shared
    ) {
        self.modelContext = modelContext
        self.monitoringSession = monitoringSession
        self.deviceDiscovery = deviceDiscovery
        self.wakeOnLanService = wakeOnLanService
        self.icmpService = icmpService
        self.networkProfileManager = networkProfileManager
        insightResponder = CompanionInsightResponder(
            service: insightService,
            isAllowed: { Self.answersInsight },
            // Never ask the model during a scan.
            isScanning: { [weak deviceDiscovery] in await MainActor.run { deviceDiscovery?.isScanning ?? false } }
        )
    }

    /// Process an incoming message and return an optional response. `authorization` is the link's
    /// (#590): nothing runs once the phone is revoked or the link closed, and model requests
    /// check it again before the model is asked.
    func handle(_ message: CompanionMessage, from _: UUID, authorization: CompanionAuthorization) async -> CompanionMessage? {
        guard authorization.isCurrent() else { return nil }
        switch message {
        case .command(let payload):
            return await handleCommand(payload)

        case .heartbeat:
            return .heartbeat(heartbeat())

        case .insightRequest(let payload):
            return await .insightResponse(insightResponder.respond(to: payload, authorization: authorization))

        case .networkProfile(let payload):
            return handleNetworkProfileSync(payload)

        default:
            return nil
        }
    }

    /// This Mac's heartbeat, advertising insight while its model can answer and the user
    /// allows it (#457). An iPhone sends insight requests only after seeing it.
    func heartbeat() -> HeartbeatPayload {
        HeartbeatPayload(capabilities: insightResponder.capabilities(
            allowed: Self.answersInsight, isScanning: deviceDiscovery.isScanning
        ))
    }

    /// Calls `send` with a fresh heartbeat whenever a scan starts or ends, so a phone stops
    /// asking while the Mac scans and starts again after (#457).
    func onScanningChange(_ send: @escaping @MainActor (HeartbeatPayload) -> Void) {
        withObservationTracking {
            _ = deviceDiscovery.isScanning
        } onChange: { [weak self] in
            // Fires before the change, off the main actor: hop over, then read the new value.
            Task { @MainActor [weak self] in
                guard let self else { return }
                send(self.heartbeat())
                self.onScanningChange(send)
            }
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
                // The friendly name when there's no hostname, as 2.2.x sent it: since #462 it's
                // kept apart, and the feed has no friendly-name field yet (#427).
                hostname: device.matchName,
                // The shown maker, as 2.2.x sent, but never a model suggestion (#449): the feed
                // has no maker or source fields yet (#427).
                vendor: device.makerExcludingSuggestions,
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
            let wasScanning = deviceDiscovery.isScanning
            let started = deviceDiscovery.rescan(.companion)
            // A scan already running still answers the request; no local network means no scan.
            return .toolResult(ToolResultPayload(
                tool: "deviceScan",
                success: started || wasScanning,
                result: started ? "Scan started" : wasScanning ? "Scan already running" : "Not connected to a local network"
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
            _ = await wakeOnLanService.wake(macAddress: mac, broadcastAddress: "255.255.255.255", port: 9)
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
        guard let localProfile = networkProfileManager.localProfile
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
