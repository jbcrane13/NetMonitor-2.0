import Foundation
import Testing
@testable import NetMonitor_macOS

/// A throwaway defaults suite holding the retention setting, so tests never touch `.standard`.
struct RetentionSuite {
    let defaults: UserDefaults
    private let name = "HistoryRetentionTests-\(UUID().uuidString)"

    init(_ value: String? = nil) {
        defaults = UserDefaults(suiteName: name) ?? .standard
        if let value {
            defaults.set(value, forKey: HistoryRetention.key)
        }
    }

    func clear() {
        defaults.removePersistentDomain(forName: name)
    }
}

@Suite("HistoryRetention policy (#487)")
struct HistoryRetentionPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func days(before date: Date, _ count: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -count, to: date) ?? date
    }

    @Test(arguments: [
        (stored: "1 day" as String?, expectedDays: 1 as Int?),
        ("7 days", 7),
        ("30 days", 30),
        ("Forever", nil),
        ("90 days", 7),   // unknown value falls back to the default
        ("forever", 7),   // matching is exact
        ("", 7),
        (nil, 7)          // missing key
    ])
    func cutoffForStoredValue(stored: String?, expectedDays: Int?) {
        let suite = RetentionSuite(stored)
        defer { suite.clear() }

        let cutoff = HistoryRetention.current(in: suite.defaults).cutoff(now: now)

        if let expectedDays {
            #expect(cutoff == days(before: now, expectedDays))
        } else {
            #expect(cutoff == nil)
        }
    }

    @Test func pickerOptionsAreTheFourStoredStrings() {
        #expect(HistoryRetention.allCases.map(\.rawValue) == ["1 day", "7 days", "30 days", "Forever"])
        #expect(HistoryRetention.default == .sevenDays)
    }
}
