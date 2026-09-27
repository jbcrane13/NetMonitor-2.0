import SwiftUI
import NetMonitorCore

struct AddNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworkProfileManager.self) private var profileManager

    /// Called with the added profile, or the existing one it matched, so the caller can select it.
    var onAdded: (NetworkProfile) -> Void = { _ in }

    @State private var gatewayIP: String = ""
    @State private var subnetCIDR: String = ""
    @State private var networkName: String = ""
    @State private var addFailed = false

    /// Mirrors `NetworkProfileManager.addProfile`'s input rules so the sheet
    /// can't submit something the manager will reject.
    enum Validation: Equatable {
        case valid
        case invalidGateway
        case invalidSubnet
        case gatewayOutsideSubnet
    }

    static func validate(gateway: String, subnet: String) -> Validation {
        guard let gatewayValue = NetworkUtilities.ipv4ToUInt32(gateway) else { return .invalidGateway }
        let parts = subnet.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
        guard parts.count == 2,
              let address = NetworkUtilities.ipv4ToUInt32(String(parts[0])),
              let prefixLength = Int(parts[1]),
              prefixLength >= 0,
              prefixLength <= 32 else {
            return .invalidSubnet
        }
        let netmask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << UInt32(32 - prefixLength)
        let networkAddress = address & netmask
        let broadcastAddress = networkAddress | ~netmask
        guard gatewayValue >= networkAddress, gatewayValue <= broadcastAddress else {
            return .gatewayOutsideSubnet
        }
        return .valid
    }

    /// The gateway field's ✓/✗: a well-formed gateway that lies outside a valid subnet is
    /// wrong, even though its format is fine (#354).
    static func gatewayIndicatorIsValid(gateway: String, subnet: String) -> Bool {
        NetworkUtilities.ipv4ToUInt32(gateway) != nil
    }

    /// Adds the network and reports the resulting profile through `onAdded`.
    /// Returns false when the manager rejected it, so the sheet stays open (#348).
    static func add(
        gateway: String,
        subnet: String,
        name: String,
        to manager: NetworkProfileManager,
        onAdded: (NetworkProfile) -> Void
    ) -> Bool {
        guard let profile = manager.addProfile(gateway: gateway, subnet: subnet, name: name) else {
            return false
        }
        onAdded(profile)
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    HStack {
                        TextField("Gateway IP", text: $gatewayIP)
                            .textContentType(.URL)
                            .accessibilityIdentifier("addNetwork_textfield_gateway")

                        validationIndicator(isValid: Self.gatewayIndicatorIsValid(gateway: gatewayIP, subnet: subnetCIDR))
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
                    if addFailed {
                        Text("Couldn't add this network. Check the gateway and subnet.")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("addNetwork_label_addError")
                    } else if !gatewayIP.isEmpty && !isValidGateway {
                        Text("Enter a valid IPv4 address")
                            .foregroundStyle(.red)
                    } else if !subnetCIDR.isEmpty && !isValidCIDR {
                        Text("Enter a valid CIDR notation (e.g., 192.168.1.0/24)")
                            .foregroundStyle(.red)
                    } else if validation == .gatewayOutsideSubnet {
                        Text("The gateway must be inside the subnet")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("addNetwork_label_validationGatewayOutsideSubnet")
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
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("addNetwork_button_add")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: gatewayIP) { addFailed = false }
        .onChange(of: subnetCIDR) { addFailed = false }
    }

    private var validation: Validation {
        Self.validate(gateway: gatewayIP, subnet: subnetCIDR)
    }

    private var isValid: Bool {
        validation == .valid
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
        if Self.add(gateway: gatewayIP, subnet: subnetCIDR, name: networkName, to: profileManager, onAdded: onAdded) {
            dismiss()
        } else {
            addFailed = true
        }
    }
}

#if DEBUG
#Preview {
    AddNetworkSheet()
        .environment(NetworkProfileManager())
}
#endif
