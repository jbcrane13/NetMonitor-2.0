import Foundation
import NetMonitorCore
import os

extension LocalNetworkChangeMonitor {
    /// The Mac's network-change monitor (#359): when the Mac joins a different network while
    /// the app is open, it stops a scan of the old network and scans the new one. The same
    /// Core monitor iOS uses, with the Mac's longer debounce.
    static func rescanning(
        _ discovery: DeviceDiscoveryCoordinator,
        profileManager: NetworkProfileManager,
        pathEvents: AsyncStream<Bool> = LocalNetworkChangeMonitor.systemPathEvents(),
        debounce: Duration = .seconds(3)
    ) -> LocalNetworkChangeMonitor {
        LocalNetworkChangeMonitor(profileManager: profileManager, pathEvents: pathEvents, debounce: debounce) { [weak discovery] _ in
            Logger.discovery.notice("Local network changed: rescanning")
            guard let discovery else { return }
            // A scan of the old network would only probe addresses that aren't there any more.
            if discovery.isScanning {
                discovery.stopScan()
            }
            discovery.startLaunchScan()
        }
    }
}
