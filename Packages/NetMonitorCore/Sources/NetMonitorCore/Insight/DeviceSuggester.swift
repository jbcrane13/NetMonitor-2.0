import Foundation
import NetworkScanKit

/// Remembers, per device, what the model was last shown and what it suggested (#449), so it
/// isn't asked again while the evidence is unchanged and a dismissed suggestion stays gone.
@MainActor
public final class DeviceSuggestionStore {
    public struct Record: Codable, Equatable, Sendable {
        /// ``DeviceEvidence/fingerprint`` of the evidence the model was shown.
        public var fingerprint: String
        /// Nil when the model had nothing worth showing, or once the suggestion was accepted.
        public var suggestion: DeviceSuggestion?
        public var dismissed: Bool

        public init(fingerprint: String, suggestion: DeviceSuggestion?, dismissed: Bool = false) {
            self.fingerprint = fingerprint
            self.suggestion = suggestion
            self.dismissed = dismissed
        }
    }

    static let storageKey = "netmonitor.deviceSuggestions"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func record(for deviceID: UUID) -> Record? {
        load()[deviceID.uuidString]
    }

    public func setRecord(_ record: Record?, for deviceID: UUID) {
        var records = load()
        records[deviceID.uuidString] = record
        save(records)
    }

    public func clearAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return records
    }

    private func save(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Asks the on-device model what saved devices are and applies its answers as the
/// lowest-ranked identity source (#449, ADR-022). A suggested maker or model is written with
/// source ``IdentitySource/modelSuggestion``, so every other source replaces it. A suggested
/// type is never written until the user accepts it.
@MainActor
public final class DeviceSuggester {
    private let service: any InsightServiceProtocol
    private let store: DeviceSuggestionStore

    public init(service: any InsightServiceProtocol, store: DeviceSuggestionStore) {
        self.service = service
        self.store = store
    }

    /// Asks about each device that needs it and whose evidence changed since the model was
    /// last asked, one at a time. Stops when the task is cancelled.
    public func suggest(for devices: [LocalDevice]) async {
        guard service.isAvailable else { return }
        for device in devices {
            if Task.isCancelled {
                return
            }
            let evidence = DeviceEvidence(device: device)
            guard evidence.needsSuggestion, store.record(for: device.id)?.fingerprint != evidence.fingerprint else { continue }

            removeSuggestedValues(from: device)
            let answer = await service.suggestIdentity(evidence)
            if Task.isCancelled {
                return
            }
            let suggestion = answer.flatMap { $0.confidence == .low || $0.isEmpty ? nil : $0 }
            store.setRecord(DeviceSuggestionStore.Record(fingerprint: evidence.fingerprint, suggestion: suggestion), for: device.id)
            if let suggestion {
                device.mergeIdentity(DeviceIdentity(
                    maker: IdentityValue(suggestion.maker, source: .modelSuggestion),
                    model: IdentityValue(suggestion.model, source: .modelSuggestion)
                ))
            }
        }
    }

    /// The suggested type, shown only while the device's type is unknown.
    public func suggestedType(for device: LocalDevice) -> DeviceType? {
        guard device.deviceType == .unknown, let record = store.record(for: device.id), !record.dismissed,
              let type = record.suggestion?.deviceType, type != .unknown
        else { return nil }
        return type
    }

    /// Whether the device shows anything the model suggested: its maker, model or type.
    public func isShowingSuggestion(_ device: LocalDevice) -> Bool {
        device.identity.winningMaker(macPrefixMaker: device.vendor)?.source == .modelSuggestion
            || device.identity.model?.source == .modelSuggestion
            || suggestedType(for: device) != nil
    }

    /// Keeps what the device shows from the suggestion: a shown maker and the model become
    /// user-confirmed, and the suggested type is written while the type is unknown. A
    /// suggested maker that a MAC-prefix maker hides is dropped.
    public func accept(_ device: LocalDevice) {
        var identity = device.identity
        if identity.maker?.source == .modelSuggestion {
            let shown = identity.winningMaker(macPrefixMaker: device.vendor)?.source == .modelSuggestion
            identity.maker = shown ? identity.maker.map { IdentityValue($0.value, source: .userConfirmed) } : nil
        }
        if identity.model?.source == .modelSuggestion {
            identity.model = identity.model.map { IdentityValue($0.value, source: .userConfirmed) }
        }
        if let type = suggestedType(for: device) {
            device.deviceType = type
        }
        if identity != device.identity {
            device.identity = identity
        }
        // Accepting changes the evidence; record it so the model isn't asked about the
        // device it was just told about.
        store.setRecord(DeviceSuggestionStore.Record(fingerprint: DeviceEvidence(device: device).fingerprint, suggestion: nil), for: device.id)
    }

    /// Removes the suggestion; it doesn't come back until the evidence changes.
    public func dismiss(_ device: LocalDevice) {
        removeSuggestedValues(from: device)
        var record = store.record(for: device.id)
            ?? DeviceSuggestionStore.Record(fingerprint: DeviceEvidence(device: device).fingerprint, suggestion: nil)
        record.dismissed = true
        store.setRecord(record, for: device.id)
    }

    private func removeSuggestedValues(from device: LocalDevice) {
        let identity = device.identity.withoutSuggestions
        if identity != device.identity {
            device.identity = identity
        }
    }
}
