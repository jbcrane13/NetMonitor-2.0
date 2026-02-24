import SwiftUI
import NetMonitorCore

/// Subnet calculator tool — parses CIDR notation and shows network details
struct SubnetCalculatorToolView: View {
    @State private var viewModel = SubnetCalculatorToolViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                SubnetInputSection(viewModel: viewModel)
                examplesSection
                controlSection

                if let error = viewModel.errorMessage {
                    errorCard(error)
                }

                if let info = viewModel.subnetInfo {
                    resultsSection(info)
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Subnet Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_subnetCalculatorTool")
    }

    // MARK: - Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Examples")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Layout.itemSpacing) {
                    ForEach(viewModel.examples, id: \.cidr) { example in
                        Button(example.label) {
                            viewModel.selectExample(example.cidr)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier(
                            "subnetTool_example_\(example.cidr.replacingOccurrences(of: "/", with: "_"))"
                        )
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Controls

    private var controlSection: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            Button {
                viewModel.calculate()
            } label: {
                Label("Calculate", systemImage: "equal.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(!viewModel.canCalculate)
            .accessibilityIdentifier("subnetTool_button_calculate")

            if viewModel.hasResult {
                ToolClearButton(accessibilityID: "subnetTool_button_clear") {
                    viewModel.clear()
                }
            }
        }
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("subnetTool_card_error")
    }

    // MARK: - Results

    @ViewBuilder
    private func resultsSection(_ info: SubnetInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Results")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            GlassCard {
                VStack(spacing: 0) {
                    resultRow(label: "Network Address", value: info.networkAddress,
                              id: "subnetCalculator_label_networkAddress")
                    divider
                    resultRow(label: "Broadcast Address", value: info.broadcastAddress,
                              id: "subnetCalculator_label_broadcastAddress")
                    divider
                    resultRow(label: "Subnet Mask", value: info.subnetMask,
                              id: "subnetCalculator_label_subnetMask")
                    divider
                    resultRow(label: "First Host", value: info.firstHost,
                              id: "subnetCalculator_label_firstHost")
                    divider
                    resultRow(label: "Last Host", value: info.lastHost,
                              id: "subnetCalculator_label_lastHost")
                    divider
                    resultRow(label: "Usable Hosts", value: info.usableHosts.formatted(),
                              id: "subnetCalculator_label_hostCount")
                    divider
                    resultRow(label: "Prefix Length", value: "/\(info.prefixLength)",
                              id: "subnetCalculator_label_prefixLength")
                }
            }
        }
        .accessibilityIdentifier("subnetTool_section_results")
    }

    private var divider: some View {
        Divider()
            .background(Theme.Colors.glassBorder)
            .padding(.vertical, 8)
    }

    private func resultRow(label: String, value: String, id: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .accessibilityIdentifier(id)
    }
}

// MARK: - Input Section (isolated to reduce re-renders on keystrokes)

private struct SubnetInputSection: View {
    @Bindable var viewModel: SubnetCalculatorToolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("CIDR Notation")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.cidrInput,
                placeholder: "e.g. 192.168.1.0/24",
                icon: "square.split.bottomrightquarter",
                keyboardType: .numbersAndPunctuation,
                accessibilityID: "subnetTool_input_cidr",
                onSubmit: {
                    if viewModel.canCalculate {
                        viewModel.calculate()
                    }
                }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SubnetCalculatorToolView()
    }
}
