import Foundation

/// SM-2 style scheduling state for one flashcard.
public struct ReviewState: Codable, Hashable, Sendable {
    public var ease: Double = 2.5
    public var intervalDays: Double = 0
    public var reps: Int = 0
    public var lapses: Int = 0
    public var due: Date = .distantPast
    public var lastReviewed: Date?

    public init() {}

    public var isNew: Bool { lastReviewed == nil }
}

public enum ReviewGrade: Int, CaseIterable, Identifiable, Sendable {
    case again, hard, good, easy
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

public enum Scheduler {
    static let minEase = 1.3
    static let relearnMinutes = 10.0

    public static func schedule(_ state: ReviewState, grade: ReviewGrade, now: Date = Date()) -> ReviewState {
        var s = state
        s.lastReviewed = now

        switch grade {
        case .again:
            s.lapses += state.reps > 0 ? 1 : 0
            s.reps = 0
            s.ease = max(minEase, s.ease - 0.2)
            s.intervalDays = relearnMinutes / (24 * 60)
        case .hard:
            s.ease = max(minEase, s.ease - 0.15)
            s.intervalDays = state.reps == 0 ? 1 : max(1, state.intervalDays * 1.2)
            s.reps += 1
        case .good:
            if state.reps == 0 {
                s.intervalDays = 1
            } else if state.reps == 1 {
                s.intervalDays = 3
            } else {
                s.intervalDays = max(state.intervalDays + 1, state.intervalDays * s.ease)
            }
            s.reps += 1
        case .easy:
            s.ease += 0.15
            s.intervalDays = state.reps == 0 ? 4 : max(state.intervalDays + 2, state.intervalDays * s.ease * 1.3)
            s.reps += 1
        }
        s.due = now.addingTimeInterval(s.intervalDays * 86_400)
        return s
    }

    /// Short label for the button, e.g. "10m", "1d", "3w".
    public static func preview(_ state: ReviewState, grade: ReviewGrade) -> String {
        let now = Date()
        let next = schedule(state, grade: grade, now: now)
        return formatInterval(next.due.timeIntervalSince(now))
    }

    public static func formatInterval(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(1, Int(minutes.rounded())))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded()))h" }
        let days = hours / 24
        if days < 14 { return "\(Int(days.rounded()))d" }
        if days < 60 { return "\(Int((days / 7).rounded()))w" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
}

/// Days you studied, for the streak counter.
public struct StudyLog: Codable, Hashable, Sendable {
    public var days: Set<String> = []
    public var reviewsByDay: [String: Int] = [:]

    public init() {}

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func record(review date: Date = Date(), calendar: Calendar = .current) {
        let k = Self.key(date, calendar: calendar)
        days.insert(k)
        reviewsByDay[k, default: 0] += 1
    }

    public mutating func recordStudy(_ date: Date = Date(), calendar: Calendar = .current) {
        days.insert(Self.key(date, calendar: calendar))
    }

    public func reviews(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        reviewsByDay[Self.key(date, calendar: calendar)] ?? 0
    }

    /// Consecutive days studied, ending today (or yesterday if you haven't studied yet today).
    public func streak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if !days.contains(Self.key(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(Self.key(yesterday, calendar: calendar)) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(Self.key(day, calendar: calendar)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}
