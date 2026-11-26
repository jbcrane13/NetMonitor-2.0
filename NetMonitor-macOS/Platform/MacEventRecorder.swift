import Foundation
import NetMonitorCore

/// The one place the Mac writes network events (#491 D7): devices joining, leaving and coming
/// back, completed scans, connectivity changes and gateway changes, each with its network's ID.
///
/// Each device event (one per device per scan, #603) names its device's primary row; the entry
/// keeps that row's ID and the device's name (`MacRuleAlerts.row`, then the device it is an
/// interface of, #594), the same lookup the alerts use. An unmatched device keeps the name the
/// scan saw.
///
/// **Flap guard:** each device logs at most one left and one joined per `flapWindow`. Events are
/// written at once with their real time; later ones in the same direction are dropped. When the
/// window closes and the device's latest state isn't the last one written, that state is written
/// then, stamped with the time it was observed, and a new window starts. A correction still
/// pending when the app quits is lost.
///
/// **Gateway:** an auto-detected profile's `gatewayIP` is its subnet's first host, so the gateway
/// is read from the routing table (`routedGateway(for:)`) at launch, on each local-network change
/// and after each scan of the local network.
@MainActor
final class MacEventRecorder {
    typealias Scheduler = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void

    static let flapWindow: TimeInterval = 10 * 60

    private let eventService: any NetworkEventServiceProtocol
    private let now: () -> Date
    private let schedule: Scheduler
    private let gatewayOf: @MainActor (NetworkProfile) -> String
    private var windows: [String: FlapWindow] = [:]
    /// The local network last seen and its gateway, for the gateway rule.
    private var lastNetwork: (profileID: UUID, gatewayIP: String)?
    /// Coordinators already subscribed to, so a second `attach` doesn't log everything twice.
    private var attached: Set<ObjectIdentifier> = []

    init(
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = MacEventRecorder.sleepThenRun,
        gatewayOf: @escaping @MainActor (NetworkProfile) -> String = MacEventRecorder.routedGateway
    ) {
        self.eventService = eventService
        self.now = now
        self.schedule = schedule
        self.gatewayOf = gatewayOf
    }

    /// Subscribes to the coordinator's device changes and completed scans. Once per coordinator.
    func attach(to discovery: DeviceDiscoveryCoordinator) {
        guard attached.insert(ObjectIdentifier(discovery)).inserted else { return }
        discovery.addDeviceChangeHandler { [weak self, weak discovery] changes, profileID in
            self?.devicesChanged(changes, devices: discovery?.discoveredDevices ?? [], profileID: profileID)
        }
        discovery.addScanCompletedHandler { [weak self, weak discovery] profileID, deviceCount in
            self?.scanCompleted(profileID: profileID, deviceCount: deviceCount)
            // A scan of the local network re-reads its gateway, which no network-change check sees.
            if let local = discovery?.networkProfileManager.localProfile, local.id == profileID {
                self?.localNetworkObserved(local)
            }
        }
    }

    // MARK: - Sources

    /// `devices` are the scanned network's rows, read for each device's name and ID.
    func devicesChanged(_ changes: [DeviceChangeEvent], devices: [LocalDevice], profileID: UUID?) {
        for change in changes {
            guard let entry = DeviceEntry(change, devices: devices, profileID: profileID) else { continue }
            record(entry)
        }
    }

    func scanCompleted(profileID: UUID?, deviceCount: Int) {
        log(NetworkEvent(
            type: .scanComplete, timestamp: now(),
            title: "Scan Complete — \(deviceCount) \(deviceCount == 1 ? "device" : "devices") found",
            networkProfileID: profileID
        ))
    }

    func connectivityChanged(isOnline: Bool, profileID: UUID, at timestamp: Date) {
        log(NetworkEvent(
            type: .connectivityChange, timestamp: timestamp,
            title: isOnline ? "Network Connected" : "Network Disconnected",
            severity: isOnline ? .success : .warning,
            networkProfileID: profileID
        ))
    }

    /// The local network, at launch and after each change. Logs a gateway change only when the
    /// network is the one seen last and its gateway differs; the first network seen and network
    /// switches log nothing (connectivity covers those).
    func localNetworkObserved(_ profile: NetworkProfile?) {
        guard let profile else {
            lastNetwork = nil
            return
        }
        let gateway = gatewayOf(profile)
        defer { lastNetwork = (profile.id, gateway) }
        guard let last = lastNetwork, last.profileID == profile.id,
              !last.gatewayIP.isEmpty, !gateway.isEmpty, last.gatewayIP != gateway
        else { return }
        log(NetworkEvent(
            type: .gatewayChange, timestamp: now(),
            title: "Gateway Changed: \(gateway)", details: "Was \(last.gatewayIP)",
            severity: .warning, networkProfileID: profile.id
        ))
    }

    /// The default route's gateway when it is on `profile`'s network (not a VPN's), else the
    /// profile's own gateway.
    static func routedGateway(for profile: NetworkProfile) -> String {
        if let gateway = NetworkUtilities.detectDefaultGateway(interface: profile.interfaceName),
           profile.network.contains(ipAddress: gateway) {
            return gateway
        }
        return profile.gatewayIP
    }

    // MARK: - Flap guard

    private struct FlapWindow {
        var written: Set<DeviceEntry.Direction>
        var lastWritten: DeviceEntry.Direction
        var latest: DeviceEntry
    }

    private func record(_ entry: DeviceEntry) {
        let observed = entry.observed(at: now())
        guard var window = windows[observed.key] else {
            write(observed)
            return
        }
        window.latest = observed
        if window.written.insert(observed.direction).inserted {
            log(observed.event)
            window.lastWritten = observed.direction
        }
        windows[observed.key] = window
    }

    /// Writes `entry` with its observed time and opens its device's window.
    private func write(_ entry: DeviceEntry) {
        log(entry.event)
        windows[entry.key] = FlapWindow(written: [entry.direction], lastWritten: entry.direction, latest: entry)
        schedule(Self.flapWindow) { [weak self] in self?.closeWindow(entry.key) }
    }

    private func closeWindow(_ key: String) {
        guard let window = windows.removeValue(forKey: key) else { return }
        if window.latest.direction != window.lastWritten {
            write(window.latest)
        }
    }

    private func log(_ event: NetworkEvent) {
        eventService.log(event)
    }

    nonisolated static func sleepThenRun(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            action()
        }
    }
}

// MARK: - DeviceEntry

/// A device change as the log writes it.
@MainActor
private struct DeviceEntry {
    enum Direction { case joined, left }

    let direction: Direction
    /// The flap window's key: the MAC, else the row, else the IP.
    let key: String
    let title: String
    let details: String?
    let deviceID: UUID?
    let profileID: UUID?
    /// When the change was seen; the event's timestamp, including a trailing correction's.
    private(set) var observedAt = Date.distantPast

    init?(_ change: DeviceChangeEvent, devices: [LocalDevice], profileID: UUID?) {
        let device: (ip: String, mac: String?, name: String?, id: UUID?)
        let prefix: String
        switch change {
        case let .firstSeen(seen):
            (device, prefix, direction) = ((seen.ipAddress, seen.macAddress, seen.name, seen.deviceID), "Device Joined", .joined)
        case let .cameOnline(seen):
            (device, prefix, direction) = ((seen.ipAddress, seen.macAddress, seen.name, seen.deviceID), "Device Back Online", .joined)
        case let .wentOffline(known):
            (device, prefix, direction) = ((known.ipAddress, known.macAddress, known.name, known.deviceID), "Device Left", .left)
        case .changed:
            return nil
        }
        let (ip, mac) = (device.ip, device.mac)
        let row = MacRuleAlerts.row(deviceID: device.id, ip: ip, mac: mac, in: devices)
        // Named by the device the row is an interface of (#594); the entry keeps the event's
        // primary row ID, which resolves to the device.
        let projection = row.map { MacRuleAlerts.device(of: $0) }
        let label = projection?.displayName ?? device.name.flatMap { $0.isEmpty ? nil : $0 } ?? ip
        title = "\(prefix): \(label)"
        details = label == ip ? nil : ip
        deviceID = device.id ?? row?.id
        self.profileID = profileID
        // The event's device (its primary row, #603) first: its current interface, and so its MAC,
        // can change between scans. Then the MAC: a row can be missing from one scan's rows and
        // present in the next.
        key = device.id?.uuidString ?? mac.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? row?.id.uuidString ?? ip
    }

    func observed(at timestamp: Date) -> DeviceEntry {
        var entry = self
        entry.observedAt = timestamp
        return entry
    }

    var event: NetworkEvent {
        NetworkEvent(
            type: direction == .joined ? .deviceJoined : .deviceLeft,
            timestamp: observedAt,
            title: title,
            details: details,
            severity: direction == .joined ? .success : .warning,
            deviceID: deviceID,
            networkProfileID: profileID
        )
    }
}
