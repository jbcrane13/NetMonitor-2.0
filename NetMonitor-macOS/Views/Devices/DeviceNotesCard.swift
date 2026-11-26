import SwiftUI
import NetMonitorCore

/// Device detail's Notes (#594): the row's notes, editable as before, then every other
/// interface's notes, each labelled by its address and editable on that row. New notes go to the
/// row the detail shows (the primary). Used by both device detail views.
struct DeviceNotesCard: View {
    let device: DeviceProjection
    /// The row whose notes are the editable field (the detail's device, the primary).
    let row: LocalDevice
    let isEditing: Bool
    @Binding var editedNotes: String
    /// Drafts of the other members' notes, by row ID.
    @Binding var editedMemberNotes: [UUID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Divider()

            if device.isGroup {
                interfaceLabel(row)
            }
            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(MacTheme.Colors.chartSurfaceShallow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("deviceDetail_textfield_notes")
            } else {
                if let notes = row.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(MacTheme.Colors.textSecondary)
                        .accessibilityIdentifier("deviceDetail_label_notes")
                } else {
                    Text("No notes")
                        .font(.body)
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                        .italic()
                }
            }
            ForEach(membersWithNotes, id: \.id) { member in
                memberNotes(member)
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deviceDetail_card_notes")
    }

    /// The other members whose notes are shown: those with notes, and while editing, those with a
    /// draft.
    private var membersWithNotes: [LocalDevice] {
        device.members.filter { member in
            member.id != row.id && (!(member.notes ?? "").isEmpty || (isEditing && editedMemberNotes[member.id] != nil))
        }
    }

    private func interfaceLabel(_ member: LocalDevice) -> some View {
        Text(member.ipAddress)
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundStyle(MacTheme.Colors.labelTertiary)
    }

    private func memberNotes(_ member: LocalDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            interfaceLabel(member)
            if isEditing {
                TextEditor(text: Binding(
                    get: { editedMemberNotes[member.id] ?? "" },
                    set: { editedMemberNotes[member.id] = $0 }
                ))
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .background(MacTheme.Colors.chartSurfaceShallow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("deviceDetail_textfield_notes_\(member.ipAddress)")
            } else {
                Text(member.notes ?? "")
                    .font(.body)
                    .foregroundStyle(MacTheme.Colors.textSecondary)
                    .accessibilityIdentifier("deviceDetail_label_notes_\(member.ipAddress)")
            }
        }
        .padding(.top, 4)
    }

    /// The drafts `startEditing` begins with: every other member's notes.
    static func memberDrafts(_ device: DeviceProjection, row: LocalDevice) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: device.members.compactMap { member in
            guard member.id != row.id, let notes = member.notes, !notes.isEmpty else { return nil }
            return (member.id, notes)
        })
    }

    /// Writes the drafts to their rows.
    static func save(_ drafts: [UUID: String], to device: DeviceProjection) {
        for member in device.members {
            if let draft = drafts[member.id] {
                member.notes = draft.isEmpty ? nil : draft
            }
        }
    }
}
