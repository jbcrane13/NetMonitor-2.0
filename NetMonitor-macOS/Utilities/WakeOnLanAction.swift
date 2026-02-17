import SwiftUI
import NetMonitorCore

/// Observable state for Wake on LAN actions with alert support.
@MainActor
@Observable
final class WakeOnLanAction {
    private(set) var alertMessage: String?
    var showAlert: Bool = false

    private let service = WakeOnLANService()

    func wake(device: LocalDevice) async {
        guard !device.macAddress.isEmpty else {
            alertMessage = "Cannot wake \(device.displayName): No MAC address"
            showAlert = true
            return
        }

        let success = await service.wake(macAddress: device.macAddress, broadcastAddress: "255.255.255.255", port: 9)
        if success {
            alertMessage = "Magic packet sent to \(device.displayName)"
        } else {
            alertMessage = "Failed to wake \(device.displayName)"
        }
        showAlert = true
    }

    func wake(macAddress: String, displayName: String) async {
        let success = await service.wake(macAddress: macAddress, broadcastAddress: "255.255.255.255", port: 9)
        if success {
            alertMessage = "Magic packet sent to \(displayName)"
        } else {
            alertMessage = "Failed to wake \(displayName)"
        }
        showAlert = true
    }

    func dismissAlert() {
        showAlert = false
        alertMessage = nil
    }
}

// MARK: - View Modifier

struct WakeOnLanAlertModifier: ViewModifier {
    @Bindable var action: WakeOnLanAction

    func body(content: Content) -> some View {
        content
            .alert("Wake on LAN", isPresented: $action.showAlert) {
                Button("OK", role: .cancel) { action.dismissAlert() }
            } message: {
                Text(action.alertMessage ?? "")
            }
    }
}

extension View {
    func wakeOnLanAlert(_ action: WakeOnLanAction) -> some View {
        modifier(WakeOnLanAlertModifier(action: action))
    }
}
