import NetMonitorCore
import SwiftData
import SwiftUI

/// Device detail's grouping actions (#594 PR2), shared by both detail views: the suggestion
/// banner ("Same Bonjour name as X: same device?") and "Same device as…". The logic and the reads
/// are `DeviceGroupingViewModel`'s, from the environment; this view only shows its state.
struct DeviceGroupingSection: View {
    let device: DeviceProjection

    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var showPicker = false
    /// This view's token, so a late close of a view grouping replaced forgets nothing.
    @State private var viewer = UUID()

    var body: some View {
        if let grouping {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(grouping.suggestions, id: \.id) { other in
                    suggestionBanner(other, grouping)
                }
                Button {
                    showPicker = true
                } label: {
                    Label("Same device as…", systemImage: "link")
                }
                .help("Say this is the same device as another one on this network")
                .accessibilityIdentifier("deviceDetail_button_sameDeviceAs")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Read again when the device or its interfaces change (a scan, an action).
            .task(id: refreshKey) {
                grouping.show(device, in: modelContext, viewer: viewer)
            }
            .onDisappear { grouping.hide(viewer: viewer) }
            .sheet(isPresented: $showPicker) {
                // The detail window's undo manager: the sheet's goes with the sheet.
                SameDeviceAsSheet(device: device, isPresented: $showPicker, undoManager: undoManager)
            }
        }
    }

    private var refreshKey: [String] {
        [device.id.uuidString] + device.members.map { "\($0.id)/\($0.lastSeen.timeIntervalSince1970)/\($0.bonjourHost ?? "")" }
    }

    private func suggestionBanner(_ other: DeviceProjection, _ grouping: DeviceGroupingViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(MacTheme.Colors.info)
            Text(DeviceGroupingChoices.suggestion(other.displayName))
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.textPrimary)
            Spacer(minLength: 8)
            Button("Not the same device") {
                grouping.dismissSuggestion(other, for: device, in: modelContext)
            }
            .accessibilityIdentifier("deviceDetail_button_suggestionNotSameDevice_\(other.id)")
            Button("Same device") {
                grouping.group(device, with: other, in: modelContext, undoManager: undoManager)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("deviceDetail_button_suggestionSameDevice_\(other.id)")
        }
        .controlSize(.small)
        .padding(12)
        .background(MacTheme.Colors.info.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(DeviceGroupingChoices.AccessibilityID.suggestionBanner(other.id))
    }
}

/// "Same device as…": the other devices on the same network, suggestions first, with search.
struct SameDeviceAsSheet: View {
    let device: DeviceProjection
    @Binding var isPresented: Bool
    /// Where Edit › Undo is registered: the window the sheet was opened from.
    let undoManager: UndoManager?

    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Same device as…")
                .font(.headline)
            Text("Choose the device \(device.displayName) is another interface of.")
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.labelSecondary)
            TextField("Search by name, address or MAC", text: Binding(get: { grouping?.search ?? "" }, set: { grouping?.search($0) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sameDeviceAs_textfield_search")
            let candidates = grouping?.candidates ?? []
            let suggested = Set(grouping?.suggestions.map(\.id) ?? [])
            List(candidates, id: \.id) { other in
                Button {
                    isPresented = false
                    grouping?.group(device, with: other, in: modelContext, undoManager: undoManager)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.displayName)
                            Text(other.members.map(\.ipAddress).joined(separator: ", "))
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if suggested.contains(other.id) {
                            Text("Same Bonjour name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(DeviceGroupingChoices.AccessibilityID.sameDeviceAsRow(other.ipAddress))
            }
            .frame(minHeight: 220)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("No Other Devices", systemImage: "desktopcomputer", description: Text("Nothing on this network matches."))
                        .accessibilityIdentifier("sameDeviceAs_label_empty")
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("sameDeviceAs_button_cancel")
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
        .onAppear { grouping?.openPicker(for: device, in: modelContext) }
        .onDisappear { grouping?.closePicker() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen_sameDeviceAs")
    }
}

/// The grouping confirmation, error and undo toast on a device detail view (#594 PR2).
struct DeviceGroupingFeedback: ViewModifier {
    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = grouping?.toast {
                    DeviceGroupToastView(toast: toast) {
                        grouping?.undo()
                    } onClose: {
                        grouping?.hideToast()
                    }
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: grouping?.toast)
            .confirmationDialog(
                DeviceGroupingChoices.overrideQuestion,
                isPresented: Binding(
                    get: { grouping?.pendingOverride != nil },
                    set: {
                        if !$0 {
                            grouping?.cancelOverride()
                        }
                    }
                )
            ) {
                Button("Group Them Anyway") {
                    grouping?.confirmOverride(in: modelContext)
                }
                .accessibilityIdentifier("deviceDetail_button_confirmGroupOverride")
                Button("Cancel", role: .cancel) {
                    grouping?.cancelOverride()
                }
                .accessibilityIdentifier("deviceDetail_button_cancelGroupOverride")
            } message: {
                Text(grouping?.pendingOverride.map { "\($0.otherName) was marked as a different device." } ?? "")
            }
            .alert(
                "Couldn't Change the Device",
                isPresented: Binding(get: { grouping?.errorMessage != nil }, set: {
                    if !$0 {
                        grouping?.clearError()
                    }
                })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(grouping?.errorMessage ?? "")
            }
    }
}

extension View {
    func deviceGroupingFeedback() -> some View {
        modifier(DeviceGroupingFeedback())
    }
}

/// "Grouped with X · Undo".
struct DeviceGroupToastView: View {
    let toast: DeviceGroupingViewModel.Toast
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.textPrimary)
                .accessibilityIdentifier("deviceDetail_label_toastMessage")
            if toast.canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("deviceDetail_button_undo")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("deviceDetail_button_dismissToast")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(MacTheme.Colors.hairline))
        .shadow(radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_toast_undo")
    }
}
