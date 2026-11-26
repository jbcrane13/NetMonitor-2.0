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

/// What the detector remembers about a device between scans (#393).
public struct KnownDevice: Codable, Sendable, Equatable {
    /// Normalised hardware address, or nil when the device has none (then it is keyed by IP).
    public var macAddress: String?
    public var ipAddress: String
    public var name: String?
    public var firstSeen: Date
    /// The last time the device answered a scan.
    public var lastSeen: Date
    /// True once the device has answered a scan; a device only ever cached is not confirmed.
    public var isConfirmed: Bool
    /// Consecutive scans the device didn't answer.
    public var missedScans: Int
    /// Reported offline after the grace period; cleared when it answers again.
    public var isOffline: Bool
    /// The saved device's primary row, when the event comes from the reconciler (#603).
    public var deviceID: UUID?

    public init(
        macAddress: String?,
        ipAddress: String,
        name: String?,
        firstSeen: Date,
        lastSeen: Date,
        isConfirmed: Bool = true,
        missedScans: Int = 0,
        isOffline: Bool = false
    ) {
        self.macAddress = DeviceMatcher.normalizedMAC(macAddress)
        self.ipAddress = ipAddress
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isConfirmed = isConfirmed
        self.missedScans = missedScans
        self.isOffline = isOffline
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

/// The scan-to-scan change registry (#393) that device events replaced (#603): the reconciler's
/// own events (`DeviceEventReducer`) are the only source now. Its stored state is deleted with the
/// saved devices; the key goes one release later.
public enum LegacyDeviceChangeRegistry {
    static let storageKey = "deviceChangeRegistry"

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
