import SwiftUI
import NetMonitorCore

/// macOS dashboard widget showing VPN connection status.
struct VPNInfoView: View {
    @State private var viewModel = VPNInfoMacViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("VPN", systemImage: "network.badge.shield.half.filled")
                    .font(.headline)
                Spacer()
                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isActive ? MacTheme.Colors.success : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isActive ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(viewModel.isActive ? .primary : .secondary)
                }
                .accessibilityIdentifier("vpn_label_status")
            }

            if viewModel.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    macRow(label: "Interface", value: viewModel.interfaceName)
                    macRow(label: "Protocol", value: viewModel.protocolName)
                    if !viewModel.connectionDuration.isEmpty {
                        macRow(label: "Duration", value: viewModel.connectionDuration)
                    }
                }
                .accessibilityIdentifier("vpnInfo_section_details")
            } else {
                Text("No VPN tunnel detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .macGlassCard()
        .accessibilityIdentifier("vpn_card_info")
        .task { viewModel.startMonitoring() }
        .onDisappear { viewModel.stopMonitoring() }
    }

    @ViewBuilder
    private func macRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontDesign(.monospaced)
        }
    }
}

// MARK: - macOS ViewModel

@MainActor
@Observable
final class VPNInfoMacViewModel {
    var status: VPNStatus = .inactive
    var connectionDuration: String = ""

    private let service: any VPNDetectionServiceProtocol = VPNDetectionService()
    private var monitorTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    var isActive: Bool { status.isActive }
    var interfaceName: String { status.interfaceName ?? "—" }
    var protocolName: String { status.protocolType.rawValue }

    func startMonitoring() {
        service.startMonitoring()
        status = service.status

        monitorTask = Task { [weak self] in
            guard let self else { return }
            let stream = service.statusStream()
// swiftlint:disable:next identifier_name
            for await s in stream {
                guard !Task.isCancelled else { break }
                status = s
                updateTimer(for: s)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        timerTask?.cancel()
        service.stopMonitoring()
    }

// swiftlint:disable:next identifier_name
    private func updateTimer(for s: VPNStatus) {
        timerTask?.cancel()
        guard s.isActive, let start = s.connectedSince else {
            connectionDuration = ""
            return
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                self?.connectionDuration = formatDuration(elapsed)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

#Preview {
    VPNInfoView()
        .frame(width: 260)
        .padding()
}
