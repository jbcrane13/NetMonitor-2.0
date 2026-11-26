import Foundation
import SwiftData
import NetMonitorCore

/// Centralised `FetchDescriptor` factory for `LocalDevice` queries.
///
/// Keeping the cap policy and sort order in one place means all views
/// automatically pick up changes to the fetch limit or sort key.
enum LocalDeviceQueries {

    /// Default row cap applied to summary and picker views.
    static let defaultLimit = 500

    /// Most-recently-seen devices sorted by `lastSeen` descending, capped at `limit`.
    /// Use for summary views that don't need the full table.
    static func recents(limit: Int = defaultLimit) -> FetchDescriptor<LocalDevice> {
        var descriptor = FetchDescriptor<LocalDevice>(
            sortBy: [SortDescriptor(\LocalDevice.lastSeen, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Devices belonging to a single network profile, sorted by `lastSeen` descending,
    /// capped at `limit`. The predicate is evaluated in the store so the cap applies
    /// to the profile-scoped set rather than the global `LocalDevice` table.
    static func forProfile(_ profileID: UUID?, limit: Int = defaultLimit) -> FetchDescriptor<LocalDevice> {
        var descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate<LocalDevice> { device in
                device.networkProfileID == profileID
            },
            sortBy: [SortDescriptor(\LocalDevice.lastSeen, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    /// Devices that have a non-empty MAC address (WoL-eligible), sorted by
    /// `lastSeen` descending, capped at `limit`. The predicate is evaluated in the
    /// store so the cap applies to the eligible set rather than the raw table.
    static func withMACAddress(limit: Int = defaultLimit) -> FetchDescriptor<LocalDevice> {
        var descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate<LocalDevice> { device in
                !device.macAddress.isEmpty
            },
            sortBy: [SortDescriptor(\LocalDevice.lastSeen, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    // MARK: - Devices, not rows (#594)

    /// `rows` (a capped fetch from one of the queries above) with every other member of the groups
    /// they belong to, so a reader never sees a group without its primary. Readers project these
    /// (or hand them to a Core reader that projects) before searching, filtering or limiting.
    static func completed(_ rows: [LocalDevice], in context: ModelContext) -> [LocalDevice] {
        (try? DeviceGroups.completingGroups(rows, in: context)) ?? rows
    }

    /// The `limit` most recently seen devices in `scope`, each with all its interfaces: Core's
    /// `DeviceGroups.recentDevices`, which pages by device, not row. The capped readers (lists,
    /// pickers, counts) read this; their `@Query` only tells them when to.
    static func recentDevices(in scope: DeviceScope, in context: ModelContext, limit: Int = defaultLimit) -> [DeviceProjection] {
        (try? DeviceGroups.recentDevices(in: scope, limit: limit, in: context)) ?? []
    }
}
