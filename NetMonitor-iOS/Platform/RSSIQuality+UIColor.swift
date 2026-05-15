import NetMonitorCore
import UIKit

extension RSSIQuality {
    /// `UIColor` projection for `UIGraphicsImageRenderer` / `CGContext`
    /// consumers (heatmap export, dot overlay drawing).
    var uiColor: UIColor {
        switch self {
        case .excellent: .systemGreen
        case .good: .systemYellow
        case .fair: .systemOrange
        case .weak: .systemRed
        }
    }
}
