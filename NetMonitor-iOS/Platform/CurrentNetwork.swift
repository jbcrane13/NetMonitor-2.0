import Foundation
import NetMonitorCore

/// The network this phone is on now (#582), for scans started without one picked: the Tools
/// scan, scheduled scans, the background scan and the Scan intent. Detected again each time, as the
/// Map and Dashboard do before they scan, so a scan's devices carry the same network ID the device
/// list, device detail and the saved rows use, never the saved profile of a network the phone left.
@MainActor
enum CurrentNetwork {
    /// The detected local network, or nil without a live interface.
    static func detected() -> NetworkProfile? {
        // A new manager loads the saved profiles and detects the local network as it starts.
        NetworkProfileManager().connectedLocalProfile
    }
}
