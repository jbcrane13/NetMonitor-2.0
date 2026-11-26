//
//  WakeOnLanToolView.swift
//  NetMonitor
//
//  Wake-on-LAN tool for sending magic packets to wake network devices.
//

import SwiftUI
import NetMonitorCore
import SwiftData

struct WakeOnLanToolView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(LocalDeviceQueries.withMACAddress()) private var devices: [LocalDevice]

    @State private var selectedDeviceID: UUID?
    /// The picked device's real MACs, every interface's (#594).
    @State private var pickedMACs: [String] = []
    @State private var macAddress = ""
    @State private var broadcastAddress = "255.255.255.255"
    @State private var isSending = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var wakeTask: Task<Void, Never>?

    private let wakeService = WakeOnLANService()

    /// One entry per device with a MAC on any interface (#594), paged by device. `devices` (the
    /// query) only triggers the refresh.
    private var pickerDevices: [DeviceProjection] {
        guard !devices.isEmpty else { return [] }
        return LocalDeviceQueries.recentDevices(network: nil, in: modelContext).filter { device in
            device.members.contains { !$0.macAddress.isEmpty }
        }
    }

    /// The MACs a send goes to: every interface's when the field still holds one of the picked
    /// device's MACs, else just the field's.
    static func macsToWake(field: String, picked: [String]) -> [String] {
        guard picked.count > 1, let mac = DeviceMatcher.normalizedMAC(field), picked.contains(mac) else { return [field] }
        return picked
    }

    var body: some View {
        ToolSheetContainer(
            title: "Wake on LAN",
            iconName: "power",
            closeAccessibilityID: "wol_button_close",
            minHeight: 300,
            inputArea: { inputArea },
            footerContent: { footer }
        )
        .onDisappear {
            wakeTask?.cancel()
            wakeTask = nil
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 16) {
            // Device selector
            HStack {
                Text("Device:")
                    .frame(width: 100, alignment: .trailing)

                Picker("Select Device", selection: $selectedDeviceID) {
                    Text("Manual Entry")
                        .tag(nil as UUID?)

                    Divider()

                    ForEach(pickerDevices) { device in
                        Text(device.displayName)
                            .tag(device.id as UUID?)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(isSending)
                .accessibilityIdentifier("wol_picker_device")
                .onChange(of: selectedDeviceID) { _, newValue in
                    if let deviceID = newValue,
                       let device = pickerDevices.first(where: { $0.id == deviceID }) {
                        macAddress = device.realMACs.first ?? device.current.macAddress
                        pickedMACs = device.realMACs
                    } else {
                        pickedMACs = []
                    }
                }
            }

            // MAC address input
            HStack {
                Text("MAC Address:")
                    .frame(width: 100, alignment: .trailing)

                TextField("AA:BB:CC:DD:EE:FF", text: $macAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isSending)
                    .accessibilityIdentifier("wol_textfield_mac")
                    .onChange(of: macAddress) { _, _ in
                        // Clear result when MAC changes
                        resultMessage = nil
                        isError = false
                    }
            }

            // Broadcast address input
            HStack {
                Text("Broadcast:")
                    .frame(width: 100, alignment: .trailing)

                TextField("255.255.255.255", text: $broadcastAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isSending)
                    .accessibilityIdentifier("wol_textfield_broadcast")
            }

            // Send button
            HStack {
                Spacer()

                Button(isSending ? "Sending..." : "Send Magic Packet") {
                    sendMagicPacket()
                }
                .buttonStyle(.borderedProminent)
                .disabled(macAddress.isEmpty || !isValidMACAddress(macAddress) || isSending)
                .accessibilityIdentifier("wol_button_send")
            }

            // Result message
            if let message = resultMessage {
                HStack {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .red : .green)

                    Text(message)
                        .foregroundStyle(isError ? .red : .green)

                    Spacer()
                }
                .padding(.top, 8)
                .accessibilityIdentifier(isError ? "wol_label_error" : "wol_label_result")
            }
        }
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(MacTheme.Colors.labelSecondary)

            Text("Wake-on-LAN requires the target device to be configured to accept magic packets.")
                .font(.caption)
                .foregroundStyle(MacTheme.Colors.labelSecondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func sendMagicPacket() {
        guard !macAddress.isEmpty, isValidMACAddress(macAddress) else {
            resultMessage = "Invalid MAC address format"
            isError = true
            return
        }

        isSending = true
        resultMessage = nil
        isError = false

        let targets = Self.macsToWake(field: macAddress, picked: pickedMACs)
        wakeTask = Task {
            var sent = 0
            for mac in targets {
                let delivered = await wakeService.wake(macAddress: mac, broadcastAddress: broadcastAddress, port: 9)
                sent += delivered ? 1 : 0
            }
            let success = sent > 0
            await MainActor.run {
                if success, targets.count > 1 {
                    resultMessage = "Magic packets sent to \(sent) of \(targets.count) interfaces"
                    isError = false
                } else if success {
                    resultMessage = "Magic packet sent successfully to \(macAddress)"
                    isError = false
                } else {
                    resultMessage = "Failed to send magic packet to \(macAddress)"
                    isError = true
                }
                isSending = false
            }
        }
    }

    private func isValidMACAddress(_ mac: String) -> Bool {
        // Remove common separators
        let cleaned = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        // Must be exactly 12 hex characters
        guard cleaned.count == 12 else {
            return false
        }

        // Must contain only hex digits
        return cleaned.allSatisfy { $0.isHexDigit }
    }
}

#Preview {
    WakeOnLanToolView()
        .modelContainer(for: [LocalDevice.self], inMemory: true)
}
