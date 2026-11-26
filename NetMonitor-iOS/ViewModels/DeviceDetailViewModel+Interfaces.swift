import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

// MARK: - A device's interfaces (#594)

extension DeviceDetailViewModel {
    /// Every member, the current one first; the loaded row alone for a device of one row.
    var members: [LocalDevice] {
        projection?.members ?? device.map { [$0] } ?? []
    }

    /// The member actions use (Ping, Port Scan, DNS): the one that answered most recently.
    var current: LocalDevice? {
        projection?.current ?? device
    }

    /// The members the Interfaces section lists: every member of a device with two or more.
    var interfaces: [LocalDevice] {
        projection?.isGroup == true ? members : []
    }

    /// Whether Wake on LAN is offered: a member supports it and has a real MAC.
    var canWake: Bool {
        members.contains(where: \.supportsWakeOnLan) && !(projection?.realMACs.isEmpty ?? true)
    }

    /// The earliest member's first sighting.
    var firstSeen: Date? {
        members.map(\.firstSeen).min()
    }

    /// The latest member's last sighting.
    var lastSeen: Date? {
        projection?.lastSeen ?? device?.lastSeen
    }

    /// The current member's MAC as shown, or "—".
    var currentMACText: String {
        let mac = current?.macAddress ?? ""
        return mac.isEmpty ? "—" : mac
    }

    /// The device's state: the best member's.
    func freshness(_ presence: PresenceSnapshot) -> PresenceFreshness {
        if let projection {
            return presence.freshness(of: projection)
        }
        return device.map { presence.freshness(of: $0) } ?? .offline
    }

    /// What removing `member` takes with it that the user entered (the shared wording); empty
    /// when nothing would be lost, so it goes without asking.
    func userContent(of member: LocalDevice) -> [String] {
        DeviceGroups.userContent(of: member)
    }

    /// The removal confirmation's message, naming what goes with the interface.
    func removalMessage(_ member: LocalDevice) -> String {
        "This deletes \(member.ipAddress) from this device, with \(ListFormatter.localizedString(byJoining: userContent(of: member)))."
    }

    /// The device report Share sends: the device's name and type, the current member's address and
    /// MAC, the best member's state, and first and last seen across members.
    func shareText(presence: PresenceSnapshot) -> String? {
        guard let device else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return """
        NetMonitor Device Report
        Name: \(device.displayName)
        IP: \(current?.ipAddress ?? device.ipAddress)
        MAC: \(currentMACText)
        Manufacturer: \(device.maker ?? "Unknown")
        Type: \(device.deviceType.rawValue)
        Status: \(freshness(presence).label)
        First Seen: \(dateFormatter.string(from: firstSeen ?? device.firstSeen))
        Last Seen: \(dateFormatter.string(from: lastSeen ?? device.lastSeen))
        """
    }
}
