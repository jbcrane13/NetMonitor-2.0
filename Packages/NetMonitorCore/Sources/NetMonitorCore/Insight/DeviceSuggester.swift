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
    /// last asked, one at a time. Stops when the task is cancelled. A device of several interfaces
    /// is asked about once, on its primary, where its type and name live (#594).
    public func suggest(for devices: [LocalDevice]) async {
        // Cancelled first: a cancelled task (its device's screen, or the store, gone) must not read
        // the rows, not even to group them.
        guard service.isAvailable, !Task.isCancelled else { return }
        for device in DeviceGroups.project(devices).map(\.primary) {
            if Task.isCancelled {
                return
            }
            let evidence = DeviceEvidence(device: device)
            guard evidence.needsSuggestion, store.record(for: device.id)?.fingerprint != evidence.fingerprint else { continue }

            removeSuggestedValues(from: device)
            let asked = store.record(for: device.id)
            let answer = await service.suggestIdentity(evidence)
            if Task.isCancelled {
                return
            }
            // The evidence changed while the model answered (a rename, a scan): the answer is about
            // evidence that no longer stands, so it isn't used or recorded, and the next pass asks
            // about the new evidence (#586).
            guard DeviceEvidence(device: device).fingerprint == evidence.fingerprint else { continue }
            // No answer because the service went away (the Mac left, or is busy and backing off) isn't
            // "nothing to suggest": nothing is recorded, so the device is asked again later, and the
            // pass stops rather than asking about every device in turn (#586). A failure while the
            // service stays available (this device's model) is recorded as before.
            if answer == nil, !service.isAvailable {
                // The record from before was about older evidence (that's why the device was asked):
                // drop it, so its suggested type can't be shown or accepted, unless the user decided
                // meanwhile.
                if store.record(for: device.id) == asked, asked != nil {
                    store.setRecord(nil, for: device.id)
                }
                return
            }
            // The user accepted or dismissed while the model was answering: keep their
            // decision, and a dismissal covers the evidence the model was just shown.
            let decided = store.record(for: device.id)
            if decided != asked {
                if var decided, decided.dismissed {
                    decided.fingerprint = evidence.fingerprint
                    store.setRecord(decided, for: device.id)
                }
                continue
            }
            let suggestion = answer.map { $0.checked(against: evidence) }
                .flatMap { $0.confidence == .low || $0.isEmpty ? nil : $0 }
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

    /// Whether the model answered about the device's current evidence (whatever it suggested).
    public func wasAsked(about device: LocalDevice) -> Bool {
        store.record(for: device.id)?.fingerprint == DeviceEvidence(device: device).fingerprint
    }

    /// Who suggested what the device shows: this device's model or the Mac's (#586); nil when it
    /// shows no suggestion.
    public func suggestionSource(for device: LocalDevice) -> InsightSource? {
        guard let record = store.record(for: device.id), !record.dismissed, let suggestion = record.suggestion else { return nil }
        return suggestion.source ?? .device
    }

    /// Whether the device shows anything the model suggested: its maker, model or type.
    public func isShowingSuggestion(_ device: LocalDevice) -> Bool {
        device.isMakerSuggested || device.isModelSuggested || suggestedType(for: device) != nil
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
