import NetMonitorCore
import SwiftUI

/// "Which network is this?" (#628 PR B): asked when the Mac's router differs from the one a
/// same-subnet network was identified by. Until it is answered, that network's saved devices read
/// "Not checked: which network is this?" and scans save nothing to them.
struct NetworkIdentityCard: View {
    let identity: NetworkIdentityController

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
        } else {
            if identity.saveFailed {
                card(
                    title: "Couldn't save which network this is",
                    detail: "Nothing was lost. Until it's saved, this network's devices are shown as history."
                ) {
                    Button("Try again") { identity.retrySave() }
                        .accessibilityIdentifier("devices_identity_retry")
                }
            }
            if let question = identity.question {
                questionCard(question)
            }
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
                    Button("Same as \(label(option))") { identity.answer(.same(option), to: question) }
                        .accessibilityIdentifier("devices_identity_same_\(option.uuidString)")
                }
                Button("New network") { identity.answer(.newNetwork, to: question) }
                    .accessibilityIdentifier("devices_identity_new")
            }
        case .isLegacy(_, _, let record):
            card(
                title: "Is this \(summary(record).name ?? "the network you used before")?",
                detail: "\(Self.describe(summary(record), now: .now)). Until you choose, its devices are shown as history."
            ) {
                Button("Yes") { identity.answer(.same(record), to: question) }
                    .accessibilityIdentifier("devices_identity_same_\(record.uuidString)")
                Button("New network") { identity.answer(.newNetwork, to: question) }
                    .accessibilityIdentifier("devices_identity_new")
            }
        case .forgottenThisConnection(_, let options):
            card(
                title: "Which network is this?",
                detail: "This network can't be recognized automatically. Your answer holds for this connection only."
            ) {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { identity.answer(.thisConnection(option), to: question) }
                        .accessibilityIdentifier("devices_identity_same_\(option.uuidString)")
                }
                Button("Somewhere else") { identity.answer(.somewhereElse, to: question) }
                    .accessibilityIdentifier("devices_identity_elsewhere")
            }
        }
    }

    private func summary(_ id: UUID) -> IdentityOptionSummary {
        identity.optionSummaries[id] ?? IdentityOptionSummary()
    }

    private func label(_ id: UUID) -> String {
        Self.describe(summary(id), now: .now)
    }

    /// "Home office · 12 saved devices · last scanned 3 days ago" (#645): what tells two sites on one
    /// subnet apart. The name only when the user gave one.
    static func describe(_ summary: IdentityOptionSummary, now: Date) -> String {
        let devices = summary.savedDevices == 1 ? "1 saved device" : "\(summary.savedDevices) saved devices"
        let scanned = summary.lastScanned.map { "last scanned \(PresenceFreshness.relativeText(since: $0, now: now))" } ?? "never scanned"
        return ([summary.name, devices, scanned] as [String?]).compactMap { $0 }.joined(separator: " · ")
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
        // What each option holds, as of now rather than when it was asked.
        .onAppear { identity.refreshOptionSummaries() }
    }
}

/// A one-line pointer to the card (#645), wherever a held network's rows read as history: the
/// dashboard's device panel for that network and the menu bar popover.
struct NetworkIdentityBanner: View {
    let identity: NetworkIdentityController
    /// The panel's network; nil (the menu bar) for whichever network is held.
    var networkID: UUID?
    let open: () -> Void

    private var applies: Bool {
        if identity.isDamaged || identity.saveFailed {
            return networkID == nil || identity.heldNetworkIDs.contains(networkID ?? UUID())
        }
        return networkID.map(identity.heldNetworkIDs.contains) ?? !identity.heldNetworkIDs.isEmpty
    }

    private var text: String {
        if identity.isDamaged {
            return "Network recognition is paused"
        }
        if identity.saveFailed {
            return "Couldn't save which network this is"
        }
        return identity.question == nil ? "Identifying which network this is…" : "Which network is this?"
    }

    var body: some View {
        if applies {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .accessibilityIdentifier("identityBanner_text")
                if identity.question != nil || identity.saveFailed || identity.isDamaged {
                    Button("Answer", action: open)
                        .controlSize(.small)
                        .accessibilityIdentifier("identityBanner_button_answer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("identityBanner")
        }
    }
}
