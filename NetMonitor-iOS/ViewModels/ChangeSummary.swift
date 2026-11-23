import Foundation

/// A summary written by the on-device model with the app's own key points, which are shown
/// word for word beside it (#453).
struct ChangeSummary: Equatable {
    let keyPoints: [String]
    let text: String
}
