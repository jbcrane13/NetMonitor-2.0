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

    /// Shows the device `row` is an interface of: its primary as ``device``, and every member,
    /// fetched in this context (a group lives on one network).
    func showDevice(of row: LocalDevice?) {
        guard let row else {
            device = nil
            projection = nil
            return
        }
        var rows = [row]
        if let group = row.deviceGroupID, let modelContext {
            let groupID: UUID? = group
            let network = row.networkProfileID
            let descriptor = FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID == groupID && $0.networkProfileID == network })
            rows = (try? modelContext.fetch(descriptor)) ?? rows
        }
        let shown = DeviceGroups.project(rows).first { $0.contains(row.id) }
        projection = shown
        device = shown?.primary ?? row
    }

    /// What removing `member` takes with it that the user entered ("custom name", "notes", …), for
    /// the confirmation; empty when nothing would be lost.
    func userContent(of member: LocalDevice) -> [String] {
        guard DeviceGroups.hasUserContent(member) else { return [] }
        var lost: [String] = []
        if !(member.customName ?? "").isEmpty {
            lost.append("its custom name")
        }
        if !(member.notes ?? "").isEmpty {
            lost.append("its notes")
        }
        if !(member.serialNumber ?? "").isEmpty || member.identity.serial?.source == .userConfirmed {
            lost.append("its serial number")
        }
        if [member.identity.maker, member.identity.model].contains(where: { $0?.source == .userConfirmed }) {
            lost.append("the maker and model you confirmed")
        }
        return lost.isEmpty ? ["what you entered for it"] : lost
    }

    /// "Remove this interface": deletes the member's row through `DeviceGroupWriter`. The device
    /// stays open on the members that remain (a group left with one becomes that row). Edits
    /// waiting in the context are saved first, since a failed removal rolls the context back.
    func removeInterface(_ member: LocalDevice) {
        guard let modelContext, let projection, projection.isGroup,
              let survivor = projection.members.first(where: { $0.id != member.id })?.id
        else { return }
        suggestionTask?.cancel()
        saveContext()
        if openedMember === member {
            openedMember = nil
            nameLookup = .confirmedByScan
        }
        do {
            try DeviceGroupWriter(context: modelContext).removeInterface(member.id)
        } catch {
            self.error = "The interface couldn't be removed. Try again."
            return
        }
        showDevice(of: Self.row(named: survivor, in: modelContext))
        startSuggestion()
    }

    /// Wake on LAN to every member's real MAC (#594): any interface may be the one that wakes it.
    /// Returns how many packets were sent.
    @discardableResult
    func wakeAllInterfaces() async -> Int {
        guard let projection else { return 0 }
        var sent = 0
        for mac in projection.realMACs where await wakeService.wake(macAddress: mac, broadcastAddress: "255.255.255.255", port: 9) {
            sent += 1
        }
        wakeResult = sent == projection.realMACs.count
            ? "Wake packet sent to \(sent) \(sent == 1 ? "interface" : "interfaces")"
            : "Wake packet sent to \(sent) of \(projection.realMACs.count) interfaces"
        return sent
    }
}
