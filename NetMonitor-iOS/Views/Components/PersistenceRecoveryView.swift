import NetMonitorCore
import SwiftUI

struct PersistenceRecoveryView: View {
    let recovery: PersistenceRecoveryState

    var body: some View {
        ContentUnavailableView {
            Label(recovery.title, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(recovery.message)
        } actions: {
            ShareLink(item: recovery.diagnosticText) {
                Label("Share Diagnostics", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("persistenceRecovery_button_shareDiagnostics")

            Text("Fully quit and reopen NetMonitor to retry. If this screen returns, share the diagnostics before reinstalling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityIdentifier("persistenceRecovery_screen")
    }
}
