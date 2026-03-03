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
    @Query private var devices: [LocalDevice]

    @State private var selectedDeviceID: UUID?
    @State private var macAddress = ""
    @State private var broadcastAddress = "255.255.255.255"
    @State private var isSending = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var wakeTask: Task<Void, Never>?

    private let wakeService = WakeOnLANService()

    // Filter devices that have MAC addresses
    private var devicesWithMAC: [LocalDevice] {
        devices.filter { !$0.macAddress.isEmpty }
    }

    // periphery:ignore
    private var selectedDevice: LocalDevice? {
        devicesWithMAC.first { $0.id == selectedDeviceID }
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

                    ForEach(devicesWithMAC) { device in
                        Text(device.displayName)
                            .tag(device.id as UUID?)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(isSending)
                .accessibilityIdentifier("wol_picker_device")
                .onChange(of: selectedDeviceID) { _, newValue in
                    if let deviceID = newValue,
                       let device = devicesWithMAC.first(where: { $0.id == deviceID }) {
                        macAddress = device.macAddress
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
            }
        }
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("Wake-on-LAN requires the target device to be configured to accept magic packets.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

        wakeTask = Task {
            let success = await wakeService.wake(macAddress: macAddress, broadcastAddress: broadcastAddress, port: 9)
            await MainActor.run {
                if success {
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
