import Foundation
import NetMonitorCore

extension NetMonitorCore.NetworkMonitorService {
    /// One path monitor for the Mac's Core consumers (Ask's live tools, #579), as on iOS. The Mac's
    /// own `NetworkMonitorService` protocol (MacNetworkMonitor) is a different type.
    static let shared = NetMonitorCore.NetworkMonitorService()
}
