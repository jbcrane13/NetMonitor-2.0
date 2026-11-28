import Foundation
import NetMonitorCore
import SwiftData

/// The Mac's network identification (#628 PR B): which same-subnet network it is on, by the IPv6
/// default router's link-local address, decided before device rows are saved.
///
/// On Mac networks distinguishable by the router hint, an unapproved mismatch requires
/// identification; while identifying, saved rows are shown as history. Limits: a change reported
/// after the commit check isn't caught; IPv4-only same-subnet sites still share rows; a cloned
/// router address isn't detected; and the iPhone has no automatic identification.
@MainActor
enum MacNetworkIdentity {
    /// Where the store lives: the user's Application Support normally; a throwaway folder and
    /// defaults suite under UI tests and the unit-test host, so they never touch the user's.
    struct Location {
        let directory: URL
        let defaults: UserDefaults

        static let uiTestSuite = "netmonitor.uitest.networkIdentity"
        static let testHostSuite = "netmonitor.testhost.networkIdentity"

        static func make(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            temporaryDirectory: URL = FileManager.default.temporaryDirectory
        ) -> Location {
            let throwaway: (String, String) -> Location = { folder, suite in
                let directory = temporaryDirectory.appending(path: folder, directoryHint: .isDirectory)
                try? FileManager.default.removeItem(at: directory)
                guard let defaults = UserDefaults(suiteName: suite) else {
                    preconditionFailure("Network identity suite \(suite) is unavailable")
                }
                defaults.removePersistentDomain(forName: suite)
                return Location(directory: directory, defaults: defaults)
            }
            if arguments.contains("--uitesting") {
                return throwaway("netmonitor-uitest-identity", uiTestSuite)
            }
            if environment["XCTestConfigurationFilePath"] != nil || arguments.contains("--in-memory-store") {
                return throwaway("netmonitor-testhost-identity-\(ProcessInfo.processInfo.processIdentifier)", testHostSuite)
            }
            let support = URL.applicationSupportDirectory.appending(path: "NetMonitor", directoryHint: .isDirectory)
            return Location(directory: support, defaults: .standard)
        }
    }

    /// The network-change monitor, made after identification is attached.
    final class WatcherRef {
        weak var watcher: LocalNetworkChangeMonitor?
    }

    /// Attaches identification for the app: detection it asks for runs through the network-change
    /// monitor, set on the returned reference once it exists, so a new ID is announced like a join.
    static func attachDetectingThroughWatcher(
        _ store: NetworkIdentityStore, discovery: DeviceDiscoveryCoordinator, profileManager: NetworkProfileManager
    ) -> WatcherRef {
        let ref = WatcherRef()
        attach(store: store, discovery: discovery, profileManager: profileManager) { ref.watcher?.checkNow() }
        return ref
    }

    /// Opens the store. Call it before the profile manager first detects: the first launch migrates
    /// the networks known before this build, not one this launch just named.
    static func openStore(
        at location: Location, profileDefaults: UserDefaults, context: ModelContext, profileIDs: @escaping @MainActor () -> [UUID]
    ) -> NetworkIdentityStore {
        NetworkIdentityStore(
            directory: location.directory,
            defaults: location.defaults,
            legacyNetworks: { NetworkProfileManager.knownLocalNetworkIDs(in: profileDefaults) },
            // A new network's ID is never one that saved rows or a saved network already use.
            reservedIDs: {
                let rows = (try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []
                return Set(rows.compactMap(\.networkProfileID)).union(profileIDs())
            }
        )
    }

    /// Connects identification to the coordinator and the profile manager, then detects again so
    /// the local network goes by its identified ID. `requestDetection` runs detection through its
    /// owner (the network-change monitor), outside the commit that asked for it.
    @discardableResult
    static func attach(
        store: NetworkIdentityStore,
        discovery: DeviceDiscoveryCoordinator,
        profileManager: NetworkProfileManager,
        readHint: @escaping @MainActor (String) -> RouterHintStatus = { RouterHint.read(interface: $0) },
        requestDetection: @escaping @MainActor () -> Void
    ) -> NetworkIdentityController {
        let identity = NetworkIdentityController(
            store: store, clock: discovery.joinClock, readHint: readHint,
            probe: { [weak discovery] legacy, _ in await discovery?.identificationProbe(legacy: legacy) },
            requestDetection: { Task { @MainActor in requestDetection() } }
        )
        discovery.identity = identity
        profileManager.localNetworkIdentity = { [weak identity] group, defaultID in
            identity?.resolveID(group: group, defaultID: defaultID) ?? defaultID
        }
        profileManager.detectLocalNetwork()
        return identity
    }
}
