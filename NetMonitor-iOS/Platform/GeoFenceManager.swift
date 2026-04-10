import Foundation
import CoreLocation
import UserNotifications

// MARK: - GeoFence Models

struct GeoFenceEntry: Codable, Identifiable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double        // metres, clamped 100...5000
    var triggerOn: GeoFenceTrigger
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200,
        triggerOn: GeoFenceTrigger = .enter,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = max(100, min(radius, 5000))
        self.triggerOn = triggerOn
        self.isEnabled = isEnabled
    }
}

enum GeoFenceTrigger: String, Codable, CaseIterable {
    case enter
    case exit
    case both

    var displayName: String {
        switch self {
        case .enter: "On Enter"
        case .exit:  "On Exit"
        case .both:  "On Enter & Exit"
        }
    }
}

struct GeoFenceEvent {
    let geofenceName: String
    let trigger: GeoFenceTrigger
    let timestamp: Date
}

// MARK: - GeoFenceManager

@MainActor
@Observable
final class GeoFenceManager: NSObject {
    static let shared = GeoFenceManager()

    private(set) var geofences: [GeoFenceEntry] = []
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastEvent: GeoFenceEvent?

    private let locationManager = CLLocationManager()
    private static let storageKey = "GeoFenceManager.geofences"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
        loadGeofences()
        if isAuthorized { restartActiveRegions() }
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways ||
        authorizationStatus == .authorizedWhenInUse
    }

    // MARK: - CRUD

    func addGeofence(_ entry: GeoFenceEntry) {
        geofences.append(entry)
        saveGeofences()
        if entry.isEnabled { startMonitoring(entry) }
    }

    // periphery:ignore
    func removeGeofence(_ entry: GeoFenceEntry) {
        stopMonitoring(entry)
        geofences.removeAll { $0.id == entry.id }
        saveGeofences()
    }

    func removeGeofences(at offsets: IndexSet) {
        for index in offsets { stopMonitoring(geofences[index]) }
        for index in offsets.reversed() { geofences.remove(at: index) }
        saveGeofences()
    }

    func toggleEnabled(_ entry: GeoFenceEntry) {
        guard let index = geofences.firstIndex(where: { $0.id == entry.id }) else { return }
        geofences[index].isEnabled.toggle()
        if geofences[index].isEnabled {
            startMonitoring(geofences[index])
        } else {
            stopMonitoring(geofences[index])
        }
        saveGeofences()
    }

    // MARK: - Region monitoring

    private func regionID(for entry: GeoFenceEntry) -> String { "geofence_\(entry.id.uuidString)" }

    private func startMonitoring(_ entry: GeoFenceEntry) {
        guard isAuthorized else { return }
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude),
            radius: min(entry.radius, locationManager.maximumRegionMonitoringDistance),
            identifier: regionID(for: entry)
        )
        region.notifyOnEntry = (entry.triggerOn == .enter || entry.triggerOn == .both)
        region.notifyOnExit  = (entry.triggerOn == .exit  || entry.triggerOn == .both)
        locationManager.startMonitoring(for: region)
    }

    private func stopMonitoring(_ entry: GeoFenceEntry) {
        let id = regionID(for: entry)
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == id }) {
            locationManager.stopMonitoring(for: region)
        }
    }

    private func restartActiveRegions() {
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix("geofence_") {
            locationManager.stopMonitoring(for: region)
        }
        for entry in geofences where entry.isEnabled { startMonitoring(entry) }
    }

    // MARK: - Notification

    private func postNotification(for entry: GeoFenceEntry, trigger: GeoFenceTrigger) {
        let content = UNMutableNotificationContent()
        content.title = "GeoFence: \(entry.name)"
        content.body  = trigger == .enter
            ? "You entered the \(entry.name) zone."
            : "You exited the \(entry.name) zone."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "geofence_\(entry.id)_\(trigger.rawValue)_\(Date().timeIntervalSinceReferenceDate)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Persistence

    private func loadGeofences() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([GeoFenceEntry].self, from: data) else { return }
        geofences = decoded
    }

    private func saveGeofences() {
        guard let data = try? JSONEncoder().encode(geofences) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - CLLocationManagerDelegate

extension GeoFenceManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized { self.restartActiveRegions() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("geofence_") else { return }
        let uuidString = String(region.identifier.dropFirst("geofence_".count))
        Task { @MainActor in
            guard let entry = self.geofences.first(where: { $0.id.uuidString == uuidString }),
                  entry.triggerOn == .enter || entry.triggerOn == .both else { return }
            self.lastEvent = GeoFenceEvent(geofenceName: entry.name, trigger: .enter, timestamp: Date())
            self.postNotification(for: entry, trigger: .enter)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("geofence_") else { return }
        let uuidString = String(region.identifier.dropFirst("geofence_".count))
        Task { @MainActor in
            guard let entry = self.geofences.first(where: { $0.id.uuidString == uuidString }),
                  entry.triggerOn == .exit || entry.triggerOn == .both else { return }
            self.lastEvent = GeoFenceEvent(geofenceName: entry.name, trigger: .exit, timestamp: Date())
            self.postNotification(for: entry, trigger: .exit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {
        // Silently absorb region monitoring errors
    }
}
