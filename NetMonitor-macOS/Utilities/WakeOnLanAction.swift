import SwiftUI
import NetMonitorCore

/// Observable state for Wake on LAN actions with alert support.
@MainActor
@Observable
final class WakeOnLanAction {
    private(set) var alertMessage: String?
    var showAlert: Bool = false

    private let service = WakeOnLANService()

    /// Sends a magic packet to every real MAC of the device's interfaces (#594): a device asleep on
    /// Ethernet may be woken by its Wi-Fi address's packet or the other way round.
    func wake(device: DeviceProjection) async {
        let macs = device.realMACs
        guard !macs.isEmpty else {
            alertMessage = "Cannot wake \(device.displayName): No MAC address"
            showAlert = true
            return
        }

        var sent = 0
        for mac in macs {
            let delivered = await service.wake(macAddress: mac, broadcastAddress: "255.255.255.255", port: 9)
            sent += delivered ? 1 : 0
        }
        if sent == 0 {
            alertMessage = "Failed to wake \(device.displayName)"
        } else if macs.count > 1 {
            alertMessage = "Magic packets sent to \(device.displayName) (\(sent) of \(macs.count) interfaces)"
        } else {
            alertMessage = "Magic packet sent to \(device.displayName)"
        }
        showAlert = true
    }

    // periphery:ignore
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
