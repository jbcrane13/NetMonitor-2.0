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
    /// Reads the iPhone's typed rules and symptoms with this Mac's model (#586).
    private let modelResponder: CompanionModelResponder
    /// The log each device's last change is read from (#585).
    private let eventService: any NetworkEventServiceProtocol
    /// The network's routed gateway, nil when the lookup fails: the phone tells networks apart by it
    /// (#585), so never the profile's first-host guess.
    private let routedGateway: @MainActor (NetworkProfile) -> String?

    /// Settings key for "Answer model requests from iPhone"; on when unset.
    nonisolated static let answersInsightKey = "netmonitor.companion.answersInsight"

    /// What the setting is until the owner changes it. On, because only a paired iPhone reaches
    /// this handler (#590); a stored value, on or off, always wins (#457).
    nonisolated static let answersInsightDefault = true

    /// Whether the user lets this Mac answer the iPhone's model requests.
    nonisolated static var answersInsight: Bool {
        UserDefaults.standard.object(forKey: answersInsightKey) as? Bool ?? answersInsightDefault
    }

    init(
        modelContext: ModelContext,
        monitoringSession: MonitoringSession,
        deviceDiscovery: DeviceDiscoveryCoordinator,
        wakeOnLanService: WakeOnLANService,
        icmpService: ICMPMonitorService,
        networkProfileManager: NetworkProfileManager,
        insightService: any InsightServiceProtocol = InsightService.shared,
        companionModel: any CompanionModelAnswering = CompanionModel.shared,
        modelAdmission: ModelAdmission = .shared,
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        routedGateway: @escaping @MainActor (NetworkProfile) -> String? = { CompanionMessageHandler.routedGateway(for: $0) }
    ) {
        self.eventService = eventService
        self.routedGateway = routedGateway
        self.modelContext = modelContext
        self.monitoringSession = monitoringSession
        self.deviceDiscovery = deviceDiscovery
        self.wakeOnLanService = wakeOnLanService
        self.icmpService = icmpService
        self.networkProfileManager = networkProfileManager
        // Never ask the model during a scan.
        let isScanning: @Sendable () async -> Bool = { [weak deviceDiscovery] in
            await MainActor.run { deviceDiscovery?.isScanning ?? false }
        }
        insightResponder = CompanionInsightResponder(
            service: insightService,
            admission: modelAdmission,
            isAllowed: { Self.answersInsight },
            isScanning: isScanning
        )
        modelResponder = CompanionModelResponder(
            model: companionModel,
            admission: modelAdmission,
            isAllowed: { Self.answersInsight },
            isScanning: isScanning
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

        case .modelRequest(let payload):
            // Nil once the phone cancelled it: nothing is sent then.
            return await modelResponder.respond(to: payload, authorization: authorization).map(CompanionMessage.modelResponse)

        case .networkProfile(let payload):
            return handleNetworkProfileSync(payload)

        default:
            return nil
        }
    }

    /// This Mac's heartbeat: always `inventory.v1` (#585), insight while its model can answer, it
    /// isn't scanning and the user allows it (#457), and `rules.v1` and `symptoms.v1` while its
    /// model can answer and the user allows it, scanning or not (#586). An iPhone sends a request
    /// only after seeing its capability.
    func heartbeat() -> HeartbeatPayload {
        let allowed = Self.answersInsight
        let insight = insightResponder.capabilities(allowed: allowed, isScanning: deviceDiscovery.isScanning) ?? []
        return HeartbeatPayload(capabilities: insight + modelResponder.capabilities(allowed: allowed) + [CompanionCapability.inventory])
    }

    /// Calls `send` with the device list after each completed scan, so a connected phone shows
    /// the Mac's inventory as it is now (#585).
    func onScanCompleted(_ send: @escaping @MainActor (CompanionMessage) -> Void) {
        deviceDiscovery.addScanCompletedHandler { [weak self] _, _ in
            guard let self else { return }
            send(self.generateDeviceList())
        }
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
        // Online means it answered the network's latest scan, and that scan is recent (#583,
        // #598): never a row within grace that missed it, nor one only the ARP cache listed.
        let presence = deviceDiscovery.presence()
        // One entry per device (#594): the device's ID (its group's, or its row's), the primary's
        // name and type, the current interface's address and MAC, online when any interface
        // answered. The phone keys nothing on the ID.
        let sentAt = Date()
        let lastChanges = lastChangeByRow()
        let deviceInfos = Self.listOrder(deviceDiscovery.projectedDevices).map { device in
            let primary = device.primary
            let scanTime = presence.lastScan(for: primary.networkProfileID)
            // Every interface with its own sighting (#594 PR2): whether it answered the latest scan,
            // and when that scan was (and its age now, on this clock, #619), so the phone counts only
            // answers newer than its own scan.
            let members = device.members.map { member in
                MemberInfo(
                    id: member.id, ipAddress: member.ipAddress, macAddress: member.macAddress.isEmpty ? nil : member.macAddress,
                    lastSeen: member.lastSeen, answeredLatestScan: presence.answeredLatestScan(member), scanTime: scanTime,
                    scanAge: scanTime.map { sentAt.timeIntervalSince($0) }, isPrimary: member.id == primary.id
                )
            }
            return DeviceInfo(
                id: device.id,
                ipAddress: device.current.ipAddress,
                macAddress: device.current.macAddress,
                // The friendly name when there's no hostname, as 2.2.x sent it: since #462 it's
                // kept apart, and the feed has no friendly-name field yet (#427).
                hostname: primary.matchName,
                // The shown maker, as 2.2.x sent, but never a model suggestion (#449): the feed
                // has no maker or source fields yet (#427).
                vendor: primary.makerExcludingSuggestions,
                deviceType: primary.deviceType.rawValue,
                isOnline: presence.answeredLatestScan(device),
                members: members,
                // What the Mac shows: any interface online, within grace.
                isDeviceOnline: presence.freshness(of: device).isOnline,
                // Ages on this clock, never dates, so the phone never compares clocks (#585, #619).
                lastSeenAge: sentAt.timeIntervalSince(device.lastSeen),
                lastChangedAge: ([device.id] + device.members.map(\.id)).compactMap { lastChanges[$0] }.max()
                    .map { sentAt.timeIntervalSince($0) },
                identity: InventoryIdentity(primary.identity)
            )
        }

        return .deviceList(Self.fitting(DeviceListPayload(devices: deviceInfos, network: inventoryNetwork(presence: presence, sentAt: sentAt))))
    }

    /// The most a list may hold, and the frame budget it must fit (#585 review 12): under the
    /// phone's 1 MiB frame cap with room to spare.
    nonisolated static let maximumListedDevices = 1000
    nonisolated static let frameBudget = CompanionFrameDecoder.defaultMaximumFrameSize * 7 / 8

    /// `list` trimmed to the most recently seen devices (they come latest first) until its frame
    /// fits `frameBudget`.
    /// A list trimmed of any device says so (`truncated`), so the phone shows it as partial (#624).
    nonisolated static func fitting(_ list: DeviceListPayload) -> DeviceListPayload {
        var count = min(list.devices.count, maximumListedDevices)
        while count > 0 {
            let trimmed = DeviceListPayload(
                devices: Array(list.devices.prefix(count)), network: list.network, truncated: count < list.devices.count ? true : nil
            )
            if let frame = try? CompanionMessage.deviceList(trimmed).encodeLengthPrefixed(), frame.count <= frameBudget {
                return trimmed
            }
            count = count * 3 / 4
        }
        return DeviceListPayload(devices: [], network: list.network, truncated: list.devices.isEmpty ? nil : true)
    }

    /// Most recently seen first; ties by address (numerically), then ID, so a trim keeps the same
    /// devices every time (#624).
    static func listOrder(_ devices: [DeviceProjection]) -> [DeviceProjection] {
        devices.sorted { lhs, rhs in
            if lhs.lastSeen != rhs.lastSeen {
                return lhs.lastSeen > rhs.lastSeen
            }
            let left = NetworkUtilities.ipv4ToUInt32(lhs.ipAddress) ?? .max, right = NetworkUtilities.ipv4ToUInt32(rhs.ipAddress) ?? .max
            if left != right {
                return left < right
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The default route's gateway when it is on `profile`'s network, else nil.
    static func routedGateway(for profile: NetworkProfile) -> String? {
        NetworkUtilities.detectRoutedGateway().flatMap { profile.network.contains(ipAddress: $0) ? $0 : nil }
    }

    /// The network the list covers and how old its latest scan is (#585).
    private func inventoryNetwork(presence: PresenceSnapshot, sentAt: Date) -> InventoryNetwork {
        // Always sent, so the phone knows an inventory Mac by its list alone (#585 review 10).
        guard let profile = deviceDiscovery.networkProfile else {
            return InventoryNetwork(subnet: nil, gatewayIP: nil, name: nil, scanAge: nil)
        }
        return InventoryNetwork(
            subnet: profile.subnetCIDR, gatewayIP: routedGateway(profile), name: profile.name,
            scanAge: presence.lastScan(for: profile.id).map { sentAt.timeIntervalSince($0) }
        )
    }

    /// Each row's latest joined or left entry in the event log (#585): entries name the device's
    /// primary row, newest first.
    private func lastChangeByRow() -> [UUID: Date] {
        var latest: [UUID: Date] = [:]
        for event in eventService.events where event.type == .deviceJoined || event.type == .deviceLeft {
            guard let id = event.deviceID else { continue }
            latest[id] = max(latest[id] ?? .distantPast, event.timestamp)
        }
        return latest
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
            let identifying = deviceDiscovery.isIdentifyingNetwork
            let started = deviceDiscovery.rescan(.companion)
            // A scan already running still answers the request; no local network means no scan. While
            // the Mac identifies which network this is, a scan follows identification (#645).
            let result = started ? "Scan started" : wasScanning ? "Scan already running"
                : identifying ? "Identifying which network this is: a scan follows" : "Not connected to a local network"
            return .toolResult(ToolResultPayload(tool: "deviceScan", success: started || wasScanning || identifying, result: result))

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
