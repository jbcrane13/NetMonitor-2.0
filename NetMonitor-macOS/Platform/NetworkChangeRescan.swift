import Foundation
import NetMonitorCore
import os

extension LocalNetworkChangeMonitor {
    /// The Mac's network-change monitor (#359): when the Mac joins a different network while
    /// the app is open, it stops a scan of the old network and scans the new one. The same
    /// Core monitor iOS uses, with the Mac's longer debounce. `onChange` hears of the new local
    /// network first (the event recorder and connectivity monitor, #491).
    static func rescanning(
        _ discovery: DeviceDiscoveryCoordinator,
        profileManager: NetworkProfileManager,
        pathEvents: AsyncStream<Bool> = LocalNetworkChangeMonitor.systemPathEvents(),
        debounce: Duration = .seconds(3),
        onChange: (@MainActor (NetworkProfile) -> Void)? = nil
    ) -> LocalNetworkChangeMonitor {
        LocalNetworkChangeMonitor(profileManager: profileManager, pathEvents: pathEvents, debounce: debounce) { [weak discovery] local in
            onChange?(local)
            Logger.discovery.notice("Local network changed: rescanning")
            guard let discovery else { return }
            discovery.rescan(.networkChanged)
        }
    }
}
