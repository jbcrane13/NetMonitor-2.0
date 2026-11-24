//
//  RulesSettingsView.swift
//  NetMonitor
//
//  Alert rules: "when something happens, notify me" (#394).
//

import NetMonitorCore
import SwiftData
import SwiftUI

struct RulesSettingsView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    /// The app's one shared store, so every Settings window edits the same rules.
    @Environment(AlertRuleStore.self) private var store
    @Environment(DeviceDiscoveryCoordinator.self) private var discovery: DeviceDiscoveryCoordinator?
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [LocalDevice]
    @Query private var targets: [NetworkTarget]
    @State private var editing: AlertRule?
    @State private var plainRule = PlainRuleMacViewModel()

    var body: some View {
        Form {
            if plainRule.isAvailable {
                PlainRuleSection(
                    viewModel: plainRule,
                    devices: networkDevices,
                    targets: targets,
                    isScanning: discovery?.isScanning ?? false,
                    onConfirm: { plainRule.confirm(store: store, context: modelContext, session: monitoringSession) }
                )
            }
            if let loadError = store.loadError {
                SwiftUI.Section {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("rules_label_loadError")
                }
            }
            SwiftUI.Section {
                if store.rules.isEmpty {
                    Text("No rules yet. Add one to get a notification when something happens, like a printer going offline.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rules_label_empty")
                }
                ForEach(store.rules) { rule in
                    RuleRow(
                        rule: rule,
                        summary: RuleDescription.summary(rule, networks: profileManager?.profiles ?? [], devices: devices),
                        onToggle: { isOn in
                            var updated = rule
                            updated.isEnabled = isOn
                            store.update(updated)
                        },
                        onEdit: { editing = rule },
                        onDelete: { store.delete(id: rule.id) }
                    )
                }
                Button("Add Rule…") {
                    editing = AlertRule(name: "", trigger: .wentOffline)
                }
                .accessibilityIdentifier("rules_button_add")
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules run while NetMonitor is open. Each match sends a notification.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Rules")
        .onAppear { store.reload() }
        .sheet(item: $plainRule.openPortScan) { request in
            PortScannerToolView(initialHost: request.host, initialPreset: request.preset)
        }
        .sheet(item: $editing) { rule in
            RuleEditorView(
                rule: rule,
                networks: profileManager?.profiles ?? [],
                deviceName: rule.conditions.deviceID.flatMap { id in devices.first { $0.id == id }?.displayName },
                onSave: { saved in
                    if store.rules.contains(where: { $0.id == saved.id }) {
                        store.update(saved)
                    } else {
                        store.add(saved)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }
}

extension RulesSettingsView {
    /// The devices a described rule can name: the active network's, or all without one.
    private var networkDevices: [LocalDevice] {
        guard let active = profileManager?.activeProfile?.id else { return devices }
        return devices.filter { $0.networkProfileID == active }
    }
}

private struct RuleRow: View {
    let rule: AlertRule
    let summary: String
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: onToggle)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("rules_toggle_\(rule.id.uuidString)")
            Spacer()
            Button("Edit", action: onEdit)
                .accessibilityIdentifier("rules_button_edit_\(rule.id.uuidString)")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete rule")
            .accessibilityIdentifier("rules_button_delete_\(rule.id.uuidString)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rules_row_\(rule.id.uuidString)")
    }
}

/// Plain-language text for a rule, shown in the list.
enum RuleDescription {
    /// `devices` name a rule's `deviceID` by the device's current name (#450).
    static func summary(_ rule: AlertRule, networks: [NetworkProfile], devices: [LocalDevice] = []) -> String {
        var parts = [trigger(rule.trigger)]
        if let duration = rule.minimumDuration, duration > 0 {
            parts.append("for \(PlainRuleBuilder.spoken(duration))")
        }
        let conditions = rule.conditions
        if let deviceID = conditions.deviceID {
            parts.append("device \(devices.first { $0.id == deviceID }?.displayName ?? "a removed device")")
        } else if let device = conditions.device, !device.isEmpty {
            parts.append("device \(device)")
        }
        if let type = conditions.deviceType {
            parts.append("type \(type.displayName)")
        }
        if let maker = conditions.maker, !maker.isEmpty {
            parts.append("maker contains \(maker)")
        }
        if let networkID = conditions.networkID {
            parts.append("on \(networks.first { $0.id == networkID }?.displayName ?? "a removed network")")
        }
        return parts.joined(separator: " · ")
    }

    static func trigger(_ trigger: AlertRuleTrigger) -> String {
        switch trigger {
        case .cameOnline: "Comes online"
        case .wentOffline: "Goes offline"
        case .firstSeen: "First seen"
        case let .latencyAbove(milliseconds): "Latency above \(Int(milliseconds)) ms"
        }
    }
}

private struct RuleEditorView: View {
    enum TriggerKind: String, CaseIterable, Identifiable {
        case wentOffline, cameOnline, firstSeen, latencyAbove
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wentOffline: "Goes offline"
            case .cameOnline: "Comes online"
            case .firstSeen: "First seen"
            case .latencyAbove: "Latency above"
            }
        }
    }

    let networks: [NetworkProfile]
    /// The current name of the device the rule's `deviceID` names.
    let deviceName: String?
    let onSave: (AlertRule) -> Void
    let onCancel: () -> Void

    @State private var rule: AlertRule
    @State private var triggerKind: TriggerKind
    @State private var latencyThreshold: Double

    init(
        rule: AlertRule,
        networks: [NetworkProfile],
        deviceName: String? = nil,
        onSave: @escaping (AlertRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.networks = networks
        self.deviceName = deviceName
        self.onSave = onSave
        self.onCancel = onCancel
        _rule = State(initialValue: rule)
        switch rule.trigger {
        case .wentOffline:
            _triggerKind = State(initialValue: .wentOffline)
            _latencyThreshold = State(initialValue: 200)
        case .cameOnline:
            _triggerKind = State(initialValue: .cameOnline)
            _latencyThreshold = State(initialValue: 200)
        case .firstSeen:
            _triggerKind = State(initialValue: .firstSeen)
            _latencyThreshold = State(initialValue: 200)
        case let .latencyAbove(milliseconds):
            _triggerKind = State(initialValue: .latencyAbove)
            _latencyThreshold = State(initialValue: milliseconds)
        }
    }

    private var trimmedName: String { rule.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            TextField("Name", text: $rule.name, prompt: Text("Printer offline"))
                .accessibilityIdentifier("rules_field_name")

            SwiftUI.Section("When") {
                Picker("Trigger", selection: $triggerKind) {
                    ForEach(TriggerKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .accessibilityIdentifier("rules_picker_trigger")
                if triggerKind == .latencyAbove {
                    Stepper("\(Int(latencyThreshold)) ms", value: $latencyThreshold, in: 10...5000, step: 10)
                        .accessibilityIdentifier("rules_stepper_latency")
                }
            }

            if let duration = rule.minimumDuration, duration > 0 {
                HStack {
                    Text("Lasts at least \(PlainRuleBuilder.spoken(duration))")
                    Spacer()
                    Button("Remove") { rule.minimumDuration = nil }
                        .accessibilityIdentifier("rules_button_clearDuration")
                }
                .accessibilityIdentifier("rules_label_duration")
            }

            SwiftUI.Section("Only for (optional)") {
                if rule.conditions.deviceID != nil {
                    // A described rule watches one device by identity, whatever it is named (#450).
                    HStack {
                        Text("Device: \(deviceName ?? "a removed device")")
                        Spacer()
                        Button("Remove") { rule.conditions.deviceID = nil }
                            .accessibilityIdentifier("rules_button_clearDeviceID")
                    }
                    .accessibilityIdentifier("rules_label_deviceID")
                } else {
                    TextField("Device", text: optionalText(\.device), prompt: Text("IP, MAC or name"))
                        .accessibilityIdentifier("rules_field_device")
                }
                Picker("Device type", selection: $rule.conditions.deviceType) {
                    Text("Any").tag(DeviceType?.none)
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(DeviceType?.some(type))
                    }
                }
                .accessibilityIdentifier("rules_picker_deviceType")
                TextField("Maker", text: optionalText(\.maker), prompt: Text("Any"))
                    .accessibilityIdentifier("rules_field_maker")
                Picker("Network", selection: $rule.conditions.networkID) {
                    Text("Any").tag(UUID?.none)
                    ForEach(networks) { network in
                        Text(network.displayName).tag(UUID?.some(network.id))
                    }
                }
                .accessibilityIdentifier("rules_picker_network")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("rules_button_cancel")
                Button("Save") {
                    var saved = rule
                    saved.name = trimmedName
                    saved.trigger = trigger
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier("rules_button_save")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .padding()
    }

    private var trigger: AlertRuleTrigger {
        switch triggerKind {
        case .wentOffline: .wentOffline
        case .cameOnline: .cameOnline
        case .firstSeen: .firstSeen
        case .latencyAbove: .latencyAbove(milliseconds: latencyThreshold)
        }
    }

    /// Binds a text field to an optional condition; an empty field means "any".
    private func optionalText(_ keyPath: WritableKeyPath<AlertRuleConditions, String?>) -> Binding<String> {
        Binding(
            get: { rule.conditions[keyPath: keyPath] ?? "" },
            set: { rule.conditions[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    RulesSettingsView()
        .environment(AlertRuleStore())
}
