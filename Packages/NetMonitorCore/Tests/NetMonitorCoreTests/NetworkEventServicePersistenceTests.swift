import Foundation
import Testing
@testable import NetMonitorCore

@Suite("NetworkEventService persistence ordering")
struct NetworkEventServicePersistenceTests {
    /// Concurrent log and prune calls must leave the saved list equal to the in-memory one, so a
    /// newer event is never overwritten by an older snapshot (#395 review).
    @Test func concurrentLogAndPruneKeepEveryNewEventPersisted() throws {
        let suite = "NetworkEventServicePersistenceTests.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let service = NetworkEventService(storage: storage)
        let now = Date()
        for index in 0..<50 {
            service.log(NetworkEvent(type: .deviceLeft, timestamp: now.addingTimeInterval(-30 * 86400), title: "old \(index)"))
        }

        let newEvents = (0..<200).map { NetworkEvent(type: .deviceJoined, timestamp: now, title: "new \($0)") }
        DispatchQueue.concurrentPerform(iterations: newEvents.count) { index in
            service.log(newEvents[index])
            if index.isMultiple(of: 4) {
                service.removeEvents(olderThan: now.addingTimeInterval(-7 * 86400))
            }
        }
        service.removeEvents(olderThan: now.addingTimeInterval(-7 * 86400))

        let data = try #require(storage.data(forKey: "com.netmonitor.networkEvents"))
        let persisted = try JSONDecoder().decode([NetworkEvent].self, from: data)
        #expect(persisted.map(\.id) == service.events.map(\.id))
        #expect(Set(persisted.map(\.id)) == Set(newEvents.map(\.id)))
    }
}
