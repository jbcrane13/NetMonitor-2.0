import Foundation
import NetMonitorCore

/// The network this phone is on now (#582), for scans started without one picked: the Tools
/// scan, scheduled scans, the background scan and the Scan intent, and for the saved-device updater.
/// Read only: it never writes the saved profiles, so a scan can't overwrite them.
@MainActor
enum CurrentNetwork {
    /// The saved local network when a live interface is on that same network (interface and
    /// subnet); nil without a live interface, or when the phone is on a network not saved yet, so
    /// scanned devices are never filed under a network the phone has left.
    static func detected(
        active: () -> [NetworkProfile] = NetworkProfileManager.detectActiveProfiles,
        saved: () -> NetworkProfile? = { NetworkProfileManager.savedLocalProfile() }
    ) -> NetworkProfile? {
        NetworkProfileManager.currentProfile(active: active, saved: saved)
    }
}
