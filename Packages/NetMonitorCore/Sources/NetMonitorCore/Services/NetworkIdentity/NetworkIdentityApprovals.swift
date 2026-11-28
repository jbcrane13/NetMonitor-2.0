import Foundation

/// The question options and approval bookkeeping of `NetworkIdentityController` (#628 PR B, #645):
/// pure functions of the store's contents.
extension NetworkIdentityController {
    /// The networks a question offers, in order.
    public static func options(of question: IdentityQuestion) -> [UUID] {
        switch question {
        case .whichNetwork(_, _, let options), .forgottenThisConnection(_, let options): options
        case .isLegacy(_, _, let record): [record]
        }
    }

    /// Approves `key` on `id`, evicting the least recently matched approvals past the limits; a
    /// network left with none becomes `forgotten`.

    /// A network this takes the key from, left with no approval, becomes legacy if it has saved rows
    /// (`hasSavedRows`) and is removed otherwise, in the same update, so the store stays valid (#645).
    static func approve(
        hasSavedRows: @MainActor (UUID) -> Bool = { _ in true }, _ key: RouterKey, group: NetworkGroup, on id: UUID, now: Date,
        in contents: inout NetworkIdentityStore.Contents
    ) {
        let previous = contents.approvals.first { $0.group == group && $0.key == key }?.recordID
        contents.approvals.removeAll { $0.group == group && $0.key == key }
        contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id, lastMatched: now))
        if let previous, previous != id {
            releaseIfUnapproved(previous, hasSavedRows: hasSavedRows, in: &contents)
        }
        func leastRecentlyMatched(_ include: (IdentityApproval) -> Bool) -> Int? {
            contents.approvals.indices.filter { include(contents.approvals[$0]) }
                .min { (contents.approvals[$0].lastMatched ?? .distantPast) < (contents.approvals[$1].lastMatched ?? .distantPast) }
        }
        while contents.approvals.filter({ $0.recordID == id }).count > approvalsPerNetwork,
              let oldest = leastRecentlyMatched({ $0.recordID == id }) {
            contents.approvals.remove(at: oldest)
        }
        while contents.approvals.count > approvalsInAll, let oldest = leastRecentlyMatched({ _ in true }) {
            let evicted = contents.approvals.remove(at: oldest)
            if !contents.approvals.contains(where: { $0.recordID == evicted.recordID }),
               let index = contents.records.firstIndex(where: { $0.id == evicted.recordID }) {
                contents.records[index].recordClass = .forgotten
            }
        }
    }

    /// A bound network left with no approval: legacy if it has saved rows, otherwise removed.
    static func releaseIfUnapproved(
        _ id: UUID, hasSavedRows: @MainActor (UUID) -> Bool, in contents: inout NetworkIdentityStore.Contents
    ) {
        guard !contents.approvals.contains(where: { $0.recordID == id }),
              let index = contents.records.firstIndex(where: { $0.id == id }), contents.records[index].recordClass == .bound else { return }
        if hasSavedRows(id) {
            contents.records[index].recordClass = .legacyUnverified
            if !contents.legacyIDs.contains(id) {
                contents.legacyIDs.append(id)
            }
        } else {
            contents.records.remove(at: index)
        }
    }
}
