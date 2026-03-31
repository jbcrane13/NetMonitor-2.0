import SwiftUI
import NetMonitorCore

struct AddNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkProfileManager.self) private var profileManager

    @State private var gatewayIP: String = ""
    @State private var subnetCIDR: String = ""
    @State private var networkName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    HStack {
                        TextField("Gateway IP", text: $gatewayIP)
                            .textContentType(.URL)
                            .accessibilityIdentifier("addNetwork_textfield_gateway")

                        validationIndicator(isValid: isValidGateway)
                            .accessibilityIdentifier("addNetwork_label_validationGateway")
                    }

                    HStack {
                        TextField("Subnet CIDR (e.g., 192.168.1.0/24)", text: $subnetCIDR)
                            .accessibilityIdentifier("addNetwork_textfield_subnet")

                        validationIndicator(isValid: isValidCIDR)
                            .accessibilityIdentifier("addNetwork_label_validationSubnet")
                    }
                } header: {
                    Text("Network Details")
                } footer: {
                    if !gatewayIP.isEmpty && !isValidGateway {
                        Text("Enter a valid IPv4 address")
                            .foregroundStyle(.red)
                    } else if !subnetCIDR.isEmpty && !isValidCIDR {
                        Text("Enter a valid CIDR notation (e.g., 192.168.1.0/24)")
                            .foregroundStyle(.red)
                    }
                }

                SwiftUI.Section {
                    TextField("Network Name (optional)", text: $networkName)
                        .accessibilityIdentifier("addNetwork_textfield_name")
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("If left empty, a name will be generated automatically")
                }
            }
            .navigationTitle("Add Network")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("addNetwork_button_cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addNetwork()
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("addNetwork_button_add")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var isValid: Bool {
        isValidGateway && isValidCIDR
    }

    private var isValidGateway: Bool {
        NetworkUtilities.ipv4ToUInt32(gatewayIP) != nil
    }

    private var isValidCIDR: Bool {
        guard isValidCIDRFormat(subnetCIDR) else { return false }
        return true
    }

    private func isValidCIDRFormat(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2,
              let networkAddress = NetworkUtilities.ipv4ToUInt32(String(parts[0])),
              let prefixLength = Int(parts[1]),
              prefixLength >= 0,
              prefixLength <= 32 else {
            return false
        }
        return true
    }

    private func validationIndicator(isValid: Bool) -> some View {
        Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(isValid ? .green : .red)
            .font(.title3)
    }

    private func addNetwork() {
        _ = profileManager.addProfile(gateway: gatewayIP, subnet: subnetCIDR, name: networkName)
    }
}

#if DEBUG
#Preview {
    AddNetworkSheet()
        .environment(NetworkProfileManager())
}
#endif
