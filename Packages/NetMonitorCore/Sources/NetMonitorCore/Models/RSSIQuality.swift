import Foundation
import SwiftUI

/// Bucketing of a Wi-Fi RSSI value into a small set of human-readable quality
/// tiers. Centralizes the threshold ladder (`-50/-60/-70`) that was previously
/// duplicated across five sites in the iOS and macOS targets.
///
/// `label` and `color` (SwiftUI) live here. Platform-specific colour
/// projections — `UIColor` on iOS, `NSColor` on macOS — are added by extension
/// in each app target so this module stays free of UIKit/AppKit.
public enum RSSIQuality: Sendable, CaseIterable {
    case excellent
    case good
    case fair
    case weak

    public init(rssi: Int) {
        switch rssi {
        case -50...0: self = .excellent
        case -60..<(-50): self = .good
        case -70..<(-60): self = .fair
        default: self = .weak
        }
    }

    public var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .weak: "Weak"
        }
    }

    public var color: Color {
        switch self {
        case .excellent: .green
        case .good: .yellow
        case .fair: .orange
        case .weak: .red
        }
    }
}
