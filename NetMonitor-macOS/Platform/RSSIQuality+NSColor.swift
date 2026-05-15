import AppKit
import NetMonitorCore

extension RSSIQuality {
    /// `NSColor` projection for `NSGraphicsContext` consumers (heatmap canvas
    /// dot overlay drawing on macOS).
    var nsColor: NSColor {
        switch self {
        case .excellent: .systemGreen
        case .good: .systemYellow
        case .fair: .systemOrange
        case .weak: .systemRed
        }
    }
}
