import Foundation

/// Which known network an observation is (#628 PR B): an ordered algorithm, the first step that
/// applies wins. It reuses an ID only on an exact approval of the observed router key in this group;
/// it never learns anything itself (approvals come only from answers, a clear legacy overlap, or a
/// new network's own key).
public enum NetworkIdentityResolver {
    /// - Parameters:
    ///   - records: the known networks, any group; only `group`'s are considered.
    ///   - approvals: every approval; only `group`'s are considered.
    ///   - connectionAnswer: the network a connection-only answer chose for this launch and generation.
    public static func resolve(
        group: NetworkGroup, hint: RouterHintStatus, records: [IdentityRecord], approvals: [IdentityApproval], connectionAnswer: UUID?
    ) -> IdentityResolution {
        let mine = records.filter { $0.group == group }
        func ids(_ cls: IdentityRecordClass) -> [UUID] { mine.filter { $0.recordClass == cls }.map(\.id) }
        switch hint {
        case .absent, .failed:
            if let connectionAnswer, mine.contains(where: { $0.id == connectionAnswer }) {
                return .use(connectionAnswer)
            }
            // An IPv6 drop never empties a bound network (#645): the one bound network is used; several,
            // or a forgotten one, ask for this connection. The bucket is for a group with nothing bound.
            let bound = ids(.bound)
            let forgotten = ids(.forgotten)
            if bound.count == 1, forgotten.isEmpty {
                return .use(bound[0])
            }
            if !bound.isEmpty || !forgotten.isEmpty {
                return .ask(.forgottenThisConnection(group: group, options: bound + forgotten))
            }
            // Several legacy networks (after a start over, #645): each is offered, never only the first.
            let legacy = ids(.legacyUnverified)
            if legacy.count > 1 {
                return .ask(.forgottenThisConnection(group: group, options: legacy))
            }
            if let legacy = legacy.first {
                return .use(legacy)
            }
            return .bucket(ids(.bucket).first)
        case .present(let key):
            if let approval = approvals.first(where: { $0.group == group && $0.key == key }) {
                guard mine.contains(where: { $0.id == approval.recordID && $0.recordClass == .bound }) else { return .damaged }
                return .use(approval.recordID)
            }
            let bound = ids(.bound)
            let forgotten = ids(.forgotten)
            let legacy = ids(.legacyUnverified)
            if !bound.isEmpty || !forgotten.isEmpty || legacy.count > 1 {
                return .ask(.whichNetwork(group: group, key: key, options: bound + forgotten + legacy))
            }
            if let legacy = legacy.first {
                return .probeLegacy(legacy, key)
            }
            return .create(key)
        }
    }
}
