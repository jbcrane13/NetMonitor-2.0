import Foundation

/// Checks the model's heatmap advice against what the app computed (#455), on top of
/// `InsightSummarizer`'s number grounding: grounding can't tell which place a figure or a
/// direction belongs to.
extension HeatmapAdvisorRequest {
    /// Whether `answer` names only computed places and states the chosen action. A compass word
    /// must belong to a weak place or the fall-off direction ("north" passes for "the north-east
    /// corner"); a room on the plan must be one of the weak places.
    public func accepts(_ answer: String) -> Bool {
        let text = answer.lowercased()
        // Whole words, so "add" isn't found in "address".
        guard action.statedBy.contains(where: { Self.mentions(text, $0) }) else { return false }
        let allowedCompass = Set((places.compactMap(\.compass) + [falloff].compactMap { $0 }).flatMap(\.words))
        guard Self.compassWords(in: text).allSatisfy(allowedCompass.contains) else { return false }
        let allowedRooms = Set(places.compactMap(\.room).map { $0.lowercased() })
        return planRooms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && Self.mentions(text, $0) }
            .allSatisfy(allowedRooms.contains)
    }

    /// The compass words in `text`, written the way `Compass.rawValue` writes them: "north east"
    /// and "northeast" read as "north-east", "center" and "middle" as "centre".
    static func compassWords(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return compassPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { span in
                let word = text[span].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                switch word {
                case "northeast": return "north-east"
                case "northwest": return "north-west"
                case "southeast": return "south-east"
                case "southwest": return "south-west"
                case "center", "central", "middle": return "centre"
                default: return word
                }
            }
        }
    }

    /// Whether `text` has `phrase` as whole words.
    private static func mentions(_ text: String, _ phrase: String) -> Bool {
        text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#, options: .regularExpression) != nil
    }

    private static let compassPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"\b(?:north|south)[\s-]?(?:east|west)\b|\b(?:north|south|east|west|centre|center|central|middle)\b"#
    )
}

extension HeatmapSurveyStatistics.Location {
    var compass: HeatmapSurveyStatistics.Compass? {
        if case let .compass(compass) = self {
            compass
        } else {
            nil
        }
    }

    var room: String? {
        if case let .room(name) = self {
            name
        } else {
            nil
        }
    }
}

extension HeatmapSurveyStatistics.Compass {
    /// Its name and, for a corner, the two directions it combines.
    var words: [String] {
        let parts = rawValue.split(separator: "-").map(String.init)
        return parts.count > 1 ? [rawValue] + parts : [rawValue]
    }
}
