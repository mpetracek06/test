import Foundation

enum TimeBudget: Int, CaseIterable, Identifiable, Codable {
    case thirtyMin = 30, oneHour = 60, twoHours = 120, fourHours = 240, oneDay = 480

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .thirtyMin: return "30 min"
        case .oneHour: return "1 hr"
        case .twoHours: return "2 hr"
        case .fourHours: return "4 hr"
        case .oneDay: return "1 day"
        }
    }
}

enum StartingLevel: String, CaseIterable, Identifiable, Codable {
    case newToIt = "Totally new"
    case someBackground = "Some background"
    case reviewing = "Reviewing / cramming"
    var id: String { rawValue }
}

enum LearningGoal: String, CaseIterable, Identifiable, Codable {
    case passExam = "Pass an exam"
    case understand = "Actually understand it"
    case apply = "Use it in practice"
    var id: String { rawValue }
}

struct VideoResource: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
    var channel: String
    var duration: String
    /// Which part to watch and at what speed, e.g. "Watch 2:10–9:30 at 1.5x".
    var watchTip: String
    /// True when the URL appeared in Claude's live web-search results.
    var verified: Bool
}

struct StudyStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var minutes: Int
    var why: String
    var explanation: String
    var keyPoints: [String]
    var videos: [VideoResource]
    var activeRecall: [String]
    var done: Bool = false
}

struct Flashcard: Codable, Hashable, Identifiable {
    var id = UUID()
    var front: String
    var back: String
}

struct StudyGuide: Codable, Hashable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var topic: String
    var timeBudgetMinutes: Int
    var tldr: String
    var paretoConcepts: [String]
    var steps: [StudyStep]
    var flashcards: [Flashcard]
    var commonMistakes: [String]
    var skipList: [String]
    var selfTest: [String]
    var sourceNotes: String

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(steps.filter(\.done).count) / Double(steps.count)
    }
}
