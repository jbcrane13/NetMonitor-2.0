import NetMonitorCore
import SwiftData
import SwiftUI

/// "Which network is this?" (#628 PR B): asked when the Mac's router differs from the one a
/// same-subnet network was identified by. Until it is answered, that network's saved devices read
/// "Not checked: which network is this?" and scans save nothing to them.
struct NetworkIdentityCard: View {
    let identity: NetworkIdentityController
    let networks: [NetworkProfile]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if identity.isDamaged {
            card(
                title: "Network recognition is paused",
                detail: "Its saved file couldn't be read, so devices aren't saved. "
                    + "Starting over keeps your devices and asks again which network this is."
            ) {
                Button("Start over") { identity.startOver() }
                    .accessibilityIdentifier("devices_identity_startOver")
            }
        } else if let question = identity.question {
            questionCard(question)
        }
    }

    @ViewBuilder
    private func questionCard(_ question: IdentityQuestion) -> some View {
        switch question {
        case .whichNetwork(_, _, let options):
            card(
                title: "Which network is this?",
                detail: "This Mac's router changed. Until you choose, saved devices are shown as history and scans don't save to them."
            ) {
                ForEach(options, id: \.self) { option in
                    Button("Same as \(name(of: option))") { identity.answer(.same(option), to: question) }
                        .accessibilityIdentifier("devices_identity_same_\(option.uuidString)")
                }
                Button("New network") { identity.answer(.newNetwork, to: question) }
                    .accessibilityIdentifier("devices_identity_new")
            }
        case .isLegacy(_, _, let record):
            card(
                title: "Is this \(name(of: record))?",
                detail: "The network with \(savedDevices(record)). Until you choose, they're shown as history."
            ) {
                Button("Yes") { identity.answer(.same(record), to: question) }
                    .accessibilityIdentifier("devices_identity_same_\(record.uuidString)")
                Button("New network") { identity.answer(.newNetwork, to: question) }
                    .accessibilityIdentifier("devices_identity_new")
            }
        case .forgottenThisConnection(_, let options):
            card(
                title: "Is this \(options.first.map(name(of:)) ?? "a network you know")?",
                detail: "This network can't be recognized automatically. Your answer holds for this connection only."
            ) {
                ForEach(options, id: \.self) { option in
                    Button("Yes, \(name(of: option))") { identity.answer(.thisConnection(option), to: question) }
                        .accessibilityIdentifier("devices_identity_same_\(option.uuidString)")
                }
                Button("Somewhere else") { identity.answer(.somewhereElse, to: question) }
                    .accessibilityIdentifier("devices_identity_new")
            }
        }
    }

    private func card(title: String, detail: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "questionmark.circle")
                .font(.headline)
                .accessibilityIdentifier("devices_identity_title")
            Text(detail)
                .font(.callout)
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .accessibilityIdentifier("devices_identity_detail")
            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacTheme.Colors.chartSurfaceShallow, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Its own container keeps the title's and buttons' identifiers from the screen's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devices_identity_card")
    }

    private func name(of id: UUID) -> String {
        // A network the Mac isn't on has no profile: name it by what it holds, so options differ.
        networks.first { $0.id == id }?.displayName ?? "the network with \(savedDevices(id))"
    }

    private func savedDevices(_ id: UUID) -> String {
        let count = savedCount(id)
        return count == 1 ? "1 saved device" : "\(count) saved devices"
    }

    private func savedCount(_ id: UUID) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == id }))) ?? 0
    }
}
