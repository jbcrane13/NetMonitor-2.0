import Foundation
import NetMonitorCore

// MARK: - TargetProtocol Icon Names

extension TargetProtocol {
    var iconName: String {
        switch self {
        case .http, .https: return "network"
        case .icmp: return "waveform.path.ecg"
        case .tcp: return "arrow.left.arrow.right"
        }
    }
}
