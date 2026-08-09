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
                Label("Export Diagnostics", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("persistenceRecovery_button_exportDiagnostics")

            Text("Quit and reopen NetMonitor to retry. If this screen returns, export diagnostics before reinstalling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 520, minHeight: 360)
        .padding()
        .accessibilityIdentifier("persistenceRecovery_screen")
    }
}
