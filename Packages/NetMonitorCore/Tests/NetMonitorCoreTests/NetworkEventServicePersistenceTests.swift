import Foundation
import Testing
@testable import NetMonitorCore

@Suite("NetworkEventService persistence ordering")
struct NetworkEventServicePersistenceTests {
    /// Concurrent log and prune calls must leave the saved list equal to the in-memory one, so a
    /// newer event is never overwritten by an older snapshot (#395 review, file store since #491).
    @Test func concurrentLogAndPruneKeepEveryNewEventPersisted() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 0.01)
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
        service.flush()

        let persisted = try JSONDecoder().decode([NetworkEvent].self, from: Data(contentsOf: fixture.fileURL))
        #expect(persisted.map(\.id) == service.events.map(\.id))
        #expect(Set(persisted.map(\.id)) == Set(newEvents.map(\.id)))
    }
}
