import Foundation

/// What both apps offer for "Same device as…" and the grouping toasts (#594 PR2), in one place so
/// the Mac and the iPhone can't drift apart.
public enum DeviceGroupingChoices {
    /// The other devices on `device`'s network, in the picker's order: suggestions
    /// (`DeviceGroups.suggestions`) first, then the rest by name; filtered by `search` against the
    /// device's name and every interface's address, MAC, hostname and match name. Pass the
    /// network's rows, complete.
    public static func candidates(for device: DeviceProjection, among rows: [LocalDevice], now: Date, search: String = "") -> [DeviceProjection] {
        let suggested = DeviceGroups.suggestions(for: device, among: rows, now: now)
        let suggestedIDs = Set(suggested.map(\.id))
        let rest = DeviceGroups.project(rows.filter { $0.networkProfileID == device.primary.networkProfileID })
            .filter { $0.id != device.id && !suggestedIDs.contains($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return (suggested + rest).filter { matches($0, search) }
    }

    /// Whether `device` matches a picker search; an empty search matches everything.
    public static func matches(_ device: DeviceProjection, _ search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let fields = [device.displayName] + device.members.flatMap { [$0.ipAddress, $0.macAddress, $0.hostname ?? "", $0.matchName ?? ""] }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The rows "Same device as…" groups: the device the user is on (it keeps its group and its
    /// primary) and the other device's primary; the writer adds the rest of both groups.
    public static func rowIDs(joining other: DeviceProjection, to device: DeviceProjection) -> [UUID] {
        [device.primary.id, other.primary.id]
    }

    // MARK: Wording

    public static func suggestion(_ other: String) -> String { "Same Bonjour name as \(other): same device?" }
    public static func grouped(with other: String) -> String { "Grouped with \(other)" }
    public static func separated(_ address: String) -> String { "\(address) is a separate device" }
    public static let overrideQuestion = "You said these were different devices. Group them anyway?"
    public static let undoUnavailable = "Can't undo: these devices changed since."
    public static let groupedByBonjour = "Grouped by Bonjour name"

    /// The label an interface row shows for how it joined its device: "Grouped by Bonjour name"
    /// for an automatic grouping, nothing for the user's own.
    public static func label(for member: LocalDevice) -> String? {
        member.groupSource == DeviceGroupSource.bonjour.rawValue ? groupedByBonjour : nil
    }
}
