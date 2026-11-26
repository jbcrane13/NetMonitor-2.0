import Foundation

// MARK: - Inputs and outputs

/// One device as a scan saw it (#393).
public struct DeviceObservation: Sendable, Equatable {
    public var ipAddress: String
    public var macAddress: String?
    public var name: String?
    /// No answer this scan; only a cache still lists it (#378). Doesn't confirm the device.
    public var isCached: Bool
    /// The saved device's primary row (`LocalDevice.id`), when the event comes from the reconciler
    /// (#603): consumers find the device by it rather than by address.
    public var deviceID: UUID?

    public init(ipAddress: String, macAddress: String?, name: String?, isCached: Bool = false, deviceID: UUID? = nil) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.name = name
        self.isCached = isCached
        self.deviceID = deviceID
    }
}

/// A device as it was before a change (#393): the previous state a `DeviceChangeEvent` carries.
public struct KnownDevice: Sendable, Equatable {
    /// Normalised hardware address, or nil when the device has none.
    public var macAddress: String?
    public var ipAddress: String
    public var name: String?
    public var firstSeen: Date
    /// The last time the device answered a scan.
    public var lastSeen: Date
    /// The saved device's primary row, when the event comes from the reconciler (#603).
    public var deviceID: UUID?

    public init(macAddress: String?, ipAddress: String, name: String?, firstSeen: Date, lastSeen: Date, deviceID: UUID? = nil) {
        self.macAddress = DeviceMatcher.normalizedMAC(macAddress)
        self.ipAddress = ipAddress
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.deviceID = deviceID
    }
}

/// A change found by comparing a scan with the known devices (#393).
public enum DeviceChangeEvent: Sendable, Equatable {
    /// Answered a scan for the first time. Never sent for the first scan of a network.
    case firstSeen(DeviceObservation)
    /// Answered again after being reported offline.
    case cameOnline(DeviceObservation)
    /// Didn't answer for the whole grace period.
    case wentOffline(KnownDevice)
    /// Answered with a different IP address or name.
    case changed(DeviceObservation, previous: KnownDevice)
}

/// How long a device may go unanswered before it counts as offline. Both limits must be
/// reached, so one missed scan is never enough, however far apart scans are.
public struct DeviceGracePolicy: Sendable, Equatable {
    public var missedScans: Int
    public var interval: TimeInterval

    public init(missedScans: Int = 3, interval: TimeInterval = 15 * 60) {
        self.missedScans = max(2, missedScans)
        self.interval = interval
    }
}

// MARK: - The retired change registry

/// The scan-to-scan change registry (#393) and the iPhone scheduler's baseline that device events
/// replaced (#603): the reconciler's own events (`DeviceEventReducer`) are the only source now.
/// Their stored state is removed with the saved devices, and once at launch.
public enum LegacyDeviceChangeRegistry {
    static let storageKeys = ["deviceChangeRegistry", "scanScheduler_baseline"]
    static let clearedMarker = "legacyDeviceChangeRegistryCleared"

    public static func clear(defaults: UserDefaults = .standard) {
        for key in storageKeys {
            defaults.removeObject(forKey: key)
        }
    }

    /// ``clear(defaults:)`` the first time it is called with `defaults`; later calls do nothing.
    public static func clearOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: clearedMarker) else { return }
        clear(defaults: defaults)
        defaults.set(true, forKey: clearedMarker)
    }
}
