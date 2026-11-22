//
//  HistoryRetention.swift
//  NetMonitor
//
//  The "Keep measurement history" setting and the cutoff it implies (#487).
//

import Foundation

enum HistoryRetention: String, CaseIterable {
    case oneDay = "1 day"
    case sevenDays = "7 days"
    case thirtyDays = "30 days"
    case forever = "Forever"

    static let key = "netmonitor.data.historyRetention"
    static let `default`: HistoryRetention = .sevenDays

    /// The stored setting. A missing or unrecognised value falls back to `default`.
    static func current(in defaults: UserDefaults) -> HistoryRetention {
        defaults.string(forKey: key).flatMap(HistoryRetention.init(rawValue:)) ?? .default
    }

    var days: Int? {
        switch self {
        case .oneDay: return 1
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .forever: return nil
        }
    }

    /// History older than this is pruned. `nil` keeps everything.
    func cutoff(now: Date) -> Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }
}
