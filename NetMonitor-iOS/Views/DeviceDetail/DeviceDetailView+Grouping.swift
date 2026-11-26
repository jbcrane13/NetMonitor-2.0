import NetMonitorCore
import SwiftUI

// MARK: - Grouping interfaces as one device (#594 PR2)

/// "Same Bonjour name as X: same device?" on device detail, for the first suggestion; nothing
/// without one.
struct GroupSuggestionBanner: View {
    let viewModel: DeviceDetailViewModel

    var body: some View {
        if let suggestion = viewModel.grouping.suggestions.first {
            banner(suggestion)
        }
    }

    private func banner(_ suggestion: DeviceProjection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Label {
                Text(DeviceGroupingChoices.suggestion(suggestion.displayName))
                    .foregroundStyle(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "bonjour")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .font(.subheadline)
            .accessibilityIdentifier("deviceDetail_label_suggestion")

            HStack(spacing: Theme.Layout.itemSpacing) {
                Button("Same device") { viewModel.groupWith(suggestion) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("deviceDetail_button_suggestionSameDevice")
                Button("Not the same device") { viewModel.dismissGroupSuggestion(suggestion) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("deviceDetail_button_suggestionNotSameDevice")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_banner_suggestion")
    }
}

/// Opens "Same device as…": pick another device on this network that is this one.
struct SameDeviceAsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Same device as…", systemImage: "rectangle.on.rectangle")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.Colors.glassBackground)
                .cornerRadius(Theme.Layout.buttonCornerRadius)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .accessibilityIdentifier("deviceDetail_button_sameDeviceAs")
    }
}

/// "Same device as…"'s picker: the other devices on this network, suggestions first, with search.
/// A pick is handed back and grouped once the sheet is gone, so the override confirmation can show.
struct SameDeviceAsSheet: View {
    let viewModel: DeviceDetailViewModel
    let onPick: (DeviceProjection) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let candidates = viewModel.sameDeviceCandidates(matching: query)
        let suggested = candidates.filter(viewModel.isSuggested)
        let others = candidates.filter { !viewModel.isSuggested($0) }
        NavigationStack {
            List {
                if !suggested.isEmpty {
                    Section("Same Bonjour name") {
                        ForEach(suggested) { row($0) }
                    }
                }
                Section(suggested.isEmpty ? "Devices on this network" : "Other devices") {
                    ForEach(others) { row($0) }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("No Other Devices", systemImage: "rectangle.on.rectangle.slash")
                        .accessibilityIdentifier("sameDeviceAs_label_empty")
                }
            }
            .searchable(text: $query, prompt: "Name or address")
            .navigationTitle("Same Device As…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("sameDeviceAs_button_cancel")
                }
            }
            .accessibilityIdentifier("screen_sameDeviceAs")
        }
    }

    private func row(_ device: DeviceProjection) -> some View {
        Button {
            onPick(device)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .foregroundStyle(.primary)
                Text(device.members.map(\.ipAddress).joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("sameDeviceAs_row_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))")
    }
}

/// The undo toast after the user grouped or separated devices: "Grouped with X · Undo".
struct GroupingUndoToast: View {
    let viewModel: DeviceDetailViewModel
    let toast: DeviceGroupingToast

    var body: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_toastMessage")
            Spacer()
            if toast.undo != nil {
                Button("Undo") { viewModel.undoGrouping() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("deviceDetail_button_undo")
            }
            Button {
                viewModel.dismissGroupingToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("deviceDetail_button_dismissToast")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_toast_undo")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
        // Opaque under the glass, so the scrolled content doesn't show through the message.
        .background(Theme.Colors.backgroundElevated, in: RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .padding(.horizontal, Theme.Layout.screenPadding)
    }
}

/// Device detail's grouping presentations: the "Same device as…" picker, the confirmation that
/// overrides an earlier "Not the same device", and the undo toast.
struct DeviceGroupingPresentation: ViewModifier {
    let viewModel: DeviceDetailViewModel
    @Binding var showsSameDeviceAs: Bool
    /// The device picked in "Same device as…", grouped once the sheet has gone.
    @State private var picked: DeviceProjection?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showsSameDeviceAs, onDismiss: {
                if let picked {
                    viewModel.groupWith(picked)
                }
                picked = nil
            }, content: {
                SameDeviceAsSheet(viewModel: viewModel) { picked = $0 }
            })
            .confirmationDialog(
                DeviceGroupingChoices.overrideQuestion, isPresented: isConfirmingOverride, titleVisibility: .visible
            ) {
                Button("Group Anyway") { viewModel.confirmGroupOverride() }
                    .accessibilityIdentifier("deviceDetail_button_confirmGroupOverride")
                Button("Cancel", role: .cancel) { viewModel.cancelGroupOverride() }
                    .accessibilityIdentifier("deviceDetail_button_cancelGroupOverride")
            }
            .safeAreaInset(edge: .bottom) {
                if let toast = viewModel.grouping.toast {
                    GroupingUndoToast(viewModel: viewModel, toast: toast)
                }
            }
    }

    private var isConfirmingOverride: Binding<Bool> {
        Binding(get: { viewModel.grouping.pendingOverride != nil }, set: { isShown in
            if !isShown {
                viewModel.cancelGroupOverride()
            }
        })
    }
}
