//
//  CompanionSettingsView.swift
//  NetMonitor
//
//  iOS companion app connection settings.
//

import NetMonitorCore
import SwiftUI

struct CompanionSettingsView: View {
    @AppStorage("netmonitor.companion.enabled") private var companionEnabled = true
    @AppStorage("netmonitor.companion.port") private var servicePort = String(CompanionLink.defaultPort)
    // Off until the owner turns it on (#457).
    @AppStorage(CompanionMessageHandler.answersInsightKey) private var answersInsight = false

    @Environment(\.companionService) private var companionService
    @State private var model: CompanionSettingsViewModel?
    @State private var showsPairingSheet = false
    @State private var phoneToRemove: PairedPhone?

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Enable companion service", isOn: $companionEnabled)
                    .accessibilityIdentifier("settings_toggle_companionEnabled")

                if companionEnabled {
                    HStack {
                        Text("Service port")
                        Spacer()
                        TextField("Port", text: $servicePort)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("settings_textfield_servicePort")
                    }
                    // The Mac's on-device model words "Explain this" and summaries for an
                    // iPhone that can't run one (#457).
                    Toggle("Answer model requests from iPhone", isOn: $answersInsight)
                        .accessibilityIdentifier("settings_toggle_answersInsight")
                }
            } header: {
                Text("Service")
            } footer: {
                Text("Paired iPhones connect over an encrypted link. Other devices can't connect.")
            }

            if companionEnabled, let model {
                pairedPhonesSection(model)
            }

            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How to pair", systemImage: "questionmark.circle")
                        .font(.headline)

                    Text("1. Update NetMonitor on your iPhone, on the same network as this Mac")
                    Text("2. Click Pair iPhone… and scan the code with the iPhone (Settings → Connect to Mac)")
                    Text("3. Check that both screens show the same six digits, then click Pair")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Companion")
        .sheet(isPresented: $showsPairingSheet) {
            if let model {
                CompanionPairingSheet(model: model)
            }
        }
        .confirmationDialog(
            "Remove \(phoneToRemove?.name ?? "this iPhone")?",
            isPresented: Binding(get: { phoneToRemove != nil }, set: {
                if !$0 {
                    phoneToRemove = nil
                }
            }),
            presenting: phoneToRemove
        ) { phone in
            Button("Remove", role: .destructive) {
                Task { await model?.remove(phone) }
            }
            .accessibilityIdentifier("settings_button_confirmRemovePhone")
        } message: { _ in
            Text("It disconnects now and must pair again to reconnect.")
        }
        .task {
            let created = CompanionSettingsViewModel(service: companionService)
            model = created
            await created.attach()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await created.refresh()
            }
            // The panel is gone: stop receiving pairing events (#590).
            await created.detach()
        }
    }

    private func pairedPhonesSection(_ model: CompanionSettingsViewModel) -> some View {
        SwiftUI.Section {
            if model.phones.isEmpty {
                HStack {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(.secondary)
                    Text("No paired iPhones")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings_label_noPairedPhones")
            } else {
                ForEach(model.phones) { phone in
                    pairedPhoneRow(phone, isConnected: model.connectedPins.contains(phone.pin))
                }
            }

            Button("Pair iPhone…") {
                showsPairingSheet = true
            }
            .accessibilityIdentifier("settings_button_pairPhone")

            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings_label_companionError")
            }
            if let attempt = model.refusedAttemptAt {
                Text("A device that isn't paired tried to connect at \(attempt.formatted(date: .omitted, time: .shortened)). "
                    + "If it was your iPhone, update NetMonitor on it and pair it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings_label_refusedAttempt")
            }
        } header: {
            Text("Paired iPhones")
        }
    }

    private func pairedPhoneRow(_ phone: PairedPhone, isConnected: Bool) -> some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundStyle(isConnected ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(phone.name)
                Text("Paired \(phone.pairedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isConnected {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Button("Remove…") {
                phoneToRemove = phone
            }
            .accessibilityIdentifier("settings_button_removePhone_\(phone.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_row_pairedPhone_\(phone.name)")
    }
}

#Preview {
    CompanionSettingsView()
}
