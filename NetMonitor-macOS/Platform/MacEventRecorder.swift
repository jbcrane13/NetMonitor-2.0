import Foundation
import NetMonitorCore

/// The one place the Mac writes network events (#491 D7): devices joining, leaving and coming
/// back, completed scans, connectivity changes and gateway changes, each with its network's ID.
///
/// Device names come from the network's rows (`MacRuleAlerts.row` → `displayName`), the same
/// lookup the alerts use; an unmatched device keeps the name the scan saw.
///
/// **Flap guard:** each device logs at most one left and one joined per `flapWindow`. Events are
/// written at once with their real time; later ones in the same direction are dropped. When the
/// window closes and the device's latest state isn't the last one written, that state is written
/// then, and a new window starts. A correction still pending when the app quits is lost.
@MainActor
final class MacEventRecorder {
    typealias Scheduler = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Void

    static let flapWindow: TimeInterval = 10 * 60

    private let eventService: any NetworkEventServiceProtocol
    private let now: () -> Date
    private let schedule: Scheduler
    private var windows: [String: FlapWindow] = [:]
    /// The local network last seen and its gateway, for the gateway rule.
    private var lastNetwork: (profileID: UUID, gatewayIP: String)?

    init(
        eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = MacEventRecorder.sleepThenRun
    ) {
        self.eventService = eventService
        self.now = now
        self.schedule = schedule
    }

    /// Subscribes to the coordinator's device changes and completed scans.
    func attach(to discovery: DeviceDiscoveryCoordinator) {
        discovery.addDeviceChangeHandler { [weak self, weak discovery] changes, profileID in
            self?.devicesChanged(changes, devices: discovery?.discoveredDevices ?? [], profileID: profileID)
        }
        discovery.onScanCompleted = { [weak self] profileID, deviceCount in
            self?.scanCompleted(profileID: profileID, deviceCount: deviceCount)
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

    func connectivityChanged(isOnline: Bool, profileID: UUID) {
        log(NetworkEvent(
            type: .connectivityChange, timestamp: now(),
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
        defer { lastNetwork = (profile.id, profile.gatewayIP) }
        guard let last = lastNetwork, last.profileID == profile.id,
              !last.gatewayIP.isEmpty, !profile.gatewayIP.isEmpty, last.gatewayIP != profile.gatewayIP
        else { return }
        log(NetworkEvent(
            type: .gatewayChange, timestamp: now(),
            title: "Gateway Changed: \(profile.gatewayIP)", details: "Was \(last.gatewayIP)",
            severity: .warning, networkProfileID: profile.id
        ))
    }

    // MARK: - Flap guard

    private struct FlapWindow {
        var written: Set<DeviceEntry.Direction>
        var lastWritten: DeviceEntry.Direction
        var latest: DeviceEntry
    }

    private func record(_ entry: DeviceEntry) {
        guard var window = windows[entry.key] else {
            write(entry)
            return
        }
        window.latest = entry
        if window.written.insert(entry.direction).inserted {
            log(entry.event(at: now()))
            window.lastWritten = entry.direction
        }
        windows[entry.key] = window
    }

    /// Writes `entry` now and opens its device's window.
    private func write(_ entry: DeviceEntry) {
        log(entry.event(at: now()))
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
    /// The flap window's key: the row, else the MAC, else the IP.
    let key: String
    let title: String
    let details: String?
    let deviceID: UUID?
    let profileID: UUID?

    init?(_ change: DeviceChangeEvent, devices: [LocalDevice], profileID: UUID?) {
        let device: (ip: String, mac: String?, name: String?)
        let prefix: String
        switch change {
        case let .firstSeen(seen):
            (device, prefix, direction) = ((seen.ipAddress, seen.macAddress, seen.name), "Device Joined", .joined)
        case let .cameOnline(seen):
            (device, prefix, direction) = ((seen.ipAddress, seen.macAddress, seen.name), "Device Back Online", .joined)
        case let .wentOffline(known):
            (device, prefix, direction) = ((known.ipAddress, known.macAddress, known.name), "Device Left", .left)
        case .changed:
            return nil
        }
        let (ip, mac) = (device.ip, device.mac)
        let row = MacRuleAlerts.row(ip: ip, mac: mac, in: devices)
        let label = row?.displayName ?? device.name.flatMap { $0.isEmpty ? nil : $0 } ?? ip
        title = "\(prefix): \(label)"
        details = label == ip ? nil : ip
        deviceID = row?.id
        self.profileID = profileID
        key = row?.id.uuidString ?? mac.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? ip
    }

    func event(at timestamp: Date) -> NetworkEvent {
        NetworkEvent(
            type: direction == .joined ? .deviceJoined : .deviceLeft,
            timestamp: timestamp,
            title: title,
            details: details,
            severity: direction == .joined ? .success : .warning,
            deviceID: deviceID,
            networkProfileID: profileID
        )
    }
}
