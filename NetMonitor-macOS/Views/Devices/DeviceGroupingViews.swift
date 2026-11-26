import NetMonitorCore
import SwiftData
import SwiftUI

/// Device detail's grouping actions (#594 PR2), shared by both detail views: the suggestion
/// banner ("Same Bonjour name as X: same device?") and "Same device as…". The logic is
/// `DeviceGroupingViewModel`'s, from the environment.
struct DeviceGroupingSection: View {
    let device: DeviceProjection

    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var showPicker = false

    var body: some View {
        if let grouping {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(grouping.suggestions(for: device, in: modelContext), id: \.id) { other in
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
            .sheet(isPresented: $showPicker) {
                SameDeviceAsSheet(device: device, isPresented: $showPicker)
            }
        }
    }

    private func suggestionBanner(_ other: DeviceProjection, _ grouping: DeviceGroupingViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(MacTheme.Colors.info)
            Text("Same Bonjour name as \(other.displayName): same device?")
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.textPrimary)
            Spacer(minLength: 8)
            Button("Not the same device") {
                grouping.dismissSuggestion(other, for: device, in: modelContext)
            }
            .accessibilityIdentifier("deviceDetail_button_dismissGroupSuggestion")
            Button("Same device") {
                grouping.group(device, with: other, in: modelContext, undoManager: undoManager)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("deviceDetail_button_acceptGroupSuggestion")
        }
        .controlSize(.small)
        .padding(12)
        .background(MacTheme.Colors.info.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_banner_suggestion")
    }
}

/// "Same device as…": the other devices on the same network, suggestions first, with search.
struct SameDeviceAsSheet: View {
    let device: DeviceProjection
    @Binding var isPresented: Bool

    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Same device as…")
                .font(.headline)
            Text("Choose the device \(device.displayName) is another interface of.")
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.labelSecondary)
            TextField("Search by name, address or MAC", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sameDeviceAs_textfield_search")
            let candidates = grouping?.candidates(for: device, search: search, in: modelContext) ?? []
            let suggested = Set(grouping?.suggestions(for: device, in: modelContext).map(\.id) ?? [])
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
                .accessibilityIdentifier("sameDeviceAs_row_\(other.ipAddress)")
            }
            .frame(minHeight: 220)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("No Other Devices", systemImage: "desktopcomputer", description: Text("Nothing on this network matches."))
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sameDeviceAs_sheet")
    }
}

/// The grouping confirmation, error and undo toast on a device detail view (#594 PR2).
struct DeviceGroupingFeedback: ViewModifier {
    @Environment(DeviceGroupingViewModel.self) private var grouping: DeviceGroupingViewModel?

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
                DeviceGroupingViewModel.overrideQuestion,
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
                    grouping?.confirmOverride()
                }
                .accessibilityIdentifier("deviceDetail_button_confirmGroupOverride")
                Button("Cancel", role: .cancel) {
                    grouping?.cancelOverride()
                }
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
                .accessibilityIdentifier("deviceDetail_toast_message")
            if toast.canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("deviceDetail_button_undoGroup")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("deviceDetail_button_closeToast")
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
