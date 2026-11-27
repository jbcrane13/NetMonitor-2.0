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
                detail: "Its saved file couldn't be read, so devices aren't saved. Starting over keeps your devices and asks again which network this is."
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
                detail: "The network with \(savedCount(record)) saved devices. Until you choose, they're shown as history."
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .accessibilityIdentifier("devices_identity_title")
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    actions()
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(MacTheme.Colors.chartSurfaceShallow)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devices_identity_card")
    }

    private func name(of id: UUID) -> String {
        networks.first { $0.id == id }?.displayName ?? "the network you used before"
    }

    private func savedCount(_ id: UUID) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == id }))) ?? 0
    }
}
