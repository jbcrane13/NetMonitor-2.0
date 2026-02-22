import Foundation

public extension Notification.Name {
    /// Posted when network profiles are added/updated by background flows such as companion sync.
    static let networkProfilesDidChange = Notification.Name("netmonitor.networkProfilesDidChange")
}
