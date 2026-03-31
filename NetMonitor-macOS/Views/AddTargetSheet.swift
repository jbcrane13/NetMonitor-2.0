import SwiftUI
import SwiftData
import NetMonitorCore
import os

struct AddTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var selectedProtocol: TargetProtocol = .https
    @State private var checkInterval: Double = 5.0
    @State private var timeout: Double = 3.0

    var body: some View {
        NavigationStack {
            Form(content: {
                SwiftUI.Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("addTarget_textfield_name")
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .accessibilityIdentifier("addTarget_textfield_host")

                    HStack {
                        TextField("Port (optional)", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("addTarget_textfield_port")

                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Target Details")
                }

                SwiftUI.Section {
                    Picker("Protocol", selection: $selectedProtocol) {
                        ForEach(TargetProtocol.allCases, id: \.self) { protocolType in
                            Text(protocolType.rawValue)
                                .tag(protocolType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("addTarget_picker_protocol")
                } header: {
                    Text("Protocol")
                }

                SwiftUI.Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Check Interval: \(Int(checkInterval))s")
                            .font(.subheadline)
                        Slider(value: $checkInterval, in: 1...60, step: 1)
                            .accessibilityIdentifier("addTarget_slider_checkInterval")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeout: \(Int(timeout))s")
                            .font(.subheadline)
                        Slider(value: $timeout, in: 1...30, step: 1)
                            .accessibilityIdentifier("addTarget_slider_timeout")
                    }
                } header: {
                    Text("Monitoring Settings")
                }
            })
            .navigationTitle("Add Target")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("addTarget_button_cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTarget()
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("addTarget_button_add")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty
    }

    private func addTarget() {
        let portInt = Int(port)

        let target = NetworkTarget(
            name: name,
            host: host,
            port: portInt,
            targetProtocol: selectedProtocol,
            checkInterval: checkInterval,
            timeout: timeout
        )

        modelContext.insert(target)
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Failed to save new target: \(error)")
        }
    }
}

#if DEBUG
#Preview {
    AddTargetSheet()
        .modelContainer(PreviewContainer().container)
}
#endif
