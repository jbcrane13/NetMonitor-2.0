//
//  RulesSettingsView.swift
//  NetMonitor
//
//  Alert rules: "when something happens, notify me" (#394).
//

import NetMonitorCore
import SwiftUI

struct RulesSettingsView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @State private var store = AlertRuleStore()
    @State private var editing: AlertRule?

    var body: some View {
        Form {
            SwiftUI.Section {
                if store.rules.isEmpty {
                    Text("No rules yet. Add one to get a notification when something happens, like a printer going offline.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rules_label_empty")
                }
                ForEach(store.rules) { rule in
                    RuleRow(
                        rule: rule,
                        summary: RuleDescription.summary(rule, networks: profileManager?.profiles ?? []),
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
        .sheet(item: $editing) { rule in
            RuleEditorView(
                rule: rule,
                networks: profileManager?.profiles ?? [],
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
    }
}

/// Plain-language text for a rule, shown in the list.
enum RuleDescription {
    static func summary(_ rule: AlertRule, networks: [NetworkProfile]) -> String {
        var parts = [trigger(rule.trigger)]
        let conditions = rule.conditions
        if let device = conditions.device, !device.isEmpty {
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
    let onSave: (AlertRule) -> Void
    let onCancel: () -> Void

    @State private var rule: AlertRule
    @State private var triggerKind: TriggerKind
    @State private var latencyThreshold: Double

    init(rule: AlertRule, networks: [NetworkProfile], onSave: @escaping (AlertRule) -> Void, onCancel: @escaping () -> Void) {
        self.networks = networks
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

            SwiftUI.Section("Only for (optional)") {
                TextField("Device", text: optionalText(\.device), prompt: Text("IP, MAC or name"))
                    .accessibilityIdentifier("rules_field_device")
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
}
